defmodule GenAgentServer.Peers do
  @moduledoc """
  Opt-in registry and request ledger for externally owned live agent sessions.

  Configure `:peers` with `enabled: true` and optionally `store: path` and
  `claude_home: path`. Without a store, state is connection-local and volatile.
  Persist before sending, never automatically resend uncertain work, and keep
  externally owned processes alive when this server exits.
  """
  use GenServer
  alias GenAgentServer.Peers.Claude

  @terminal ~w(completed blocked failed)
  @max_entries 256
  @max_events 16
  @max_frame_bytes 131_072

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  def call(operation, args, server \\ __MODULE__) do
    GenServer.call(server, {operation, args}, 10_000)
  catch
    :exit, _ -> {:error, :peers_unavailable}
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    if Keyword.get(opts, :enabled, false) do
      {uid, 0} = System.cmd("/usr/bin/id", ["-u"])

      adapter_opts = [
        uid: String.to_integer(String.trim(uid)),
        home: Keyword.get(opts, :claude_home, Path.expand("~/.claude"))
      ]

      adapter_opts = Keyword.merge(adapter_opts, Keyword.get(opts, :adapter_opts, []))

      dir =
        Path.join(System.tmp_dir!(), "gas-peer-" <> Base.encode16(:crypto.strong_rand_bytes(6)))

      :ok = File.mkdir(dir)
      :ok = File.chmod(dir, 0o700)
      path = Path.join(dir, "inbox.sock")

      adapter = Keyword.get(opts, :adapter, Claude)

      with {:ok, data} <- load(Keyword.get(opts, :store), adapter),
           {:ok, socket} <-
             :gen_tcp.listen(0, [
               :binary,
               active: false,
               packet: :line,
               packet_size: @max_frame_bytes,
               # Line mode can truncate at the receive buffer before JSON decoding.
               buffer: @max_frame_bytes,
               backlog: 32,
               ifaddr: {:local, String.to_charlist(path)}
             ]) do
        :ok = File.chmod(path, 0o600)
        owner = self()
        acceptor = spawn_link(fn -> accept(socket, owner) end)

        {:ok,
         %{
           enabled: true,
           adapter: adapter,
           adapter_opts: adapter_opts,
           dir: dir,
           path: path,
           socket: socket,
           acceptor: acceptor,
           store: Keyword.get(opts, :store),
           data: data
         }}
      else
        {:error, reason} ->
          File.rmdir(dir)
          {:stop, reason}
      end
    else
      {:ok, %{enabled: false}}
    end
  end

  @impl true
  def handle_call(_, _, %{enabled: false} = state), do: {:reply, {:error, :peers_disabled}, state}

  def handle_call({:discover, args}, _, state) do
    candidates =
      state.adapter.discover(state.adapter_opts)
      |> Enum.filter(&(!args["name"] || &1["name"] == args["name"]))
      |> Enum.take(100)
      |> Enum.map(fn peer -> state.adapter.public(peer) end)

    bindings = state.data["bindings"] |> Map.values() |> Enum.map(&public_binding(&1, state))

    {:reply,
     {:ok,
      %{"candidates" => candidates, "bindings" => bindings, "durable" => state.store != nil}},
     state}
  end

  def handle_call({:bind, args}, _, state) do
    with :ok <- address(args["address"], state.adapter.provider()),
         {:ok, peer} <- select_peer(args["session_id"], state),
         :ok <- binding_available(state.data, args["address"], args["session_id"]),
         true <-
           map_size(state.data["bindings"]) < @max_entries or
             Map.has_key?(state.data["bindings"], args["address"]) do
      binding =
        peer |> Map.drop(~w(availability reason status)) |> Map.put("address", args["address"])

      persist_reply(
        state,
        put_in(state.data, ["bindings", args["address"]], binding),
        public_binding(binding, state)
      )
    else
      {:error, _} = error -> {:reply, error, state}
      [] -> {:reply, {:error, :peer_not_found}, state}
      false -> {:reply, {:error, :peer_registry_full}, state}
      _ -> {:reply, {:error, :ambiguous_peer}, state}
    end
  end

  def handle_call({:send, args}, _, state) do
    existing =
      Enum.find(Map.values(state.data["requests"]), &(&1["key"] == args["idempotency_key"]))

    cond do
      not valid_message?(args) ->
        {:reply, {:error, :invalid_peer_message}, state}

      existing &&
          (existing["address"] != args["address"] || existing["message"] != args["message"]) ->
        {:reply, {:error, :idempotency_conflict}, state}

      existing ->
        {:reply, {:ok, Map.put(public_request(existing, state), "duplicate", true)}, state}

      map_size(state.data["requests"]) >= @max_entries ->
        {:reply, {:error, :peer_ledger_full}, state}

      true ->
        send_new(args, state)
    end
  end

  def handle_call({:result, args}, _, state) do
    case Map.fetch(state.data["requests"], args["id"]) do
      {:ok, request} -> {:reply, {:ok, public_request(request, state)}, state}
      :error -> {:reply, {:error, :peer_request_not_found}, state}
    end
  end

  @impl true
  def handle_info({:EXIT, pid, _reason}, %{acceptor: pid} = state) do
    if Port.info(state.socket) do
      owner = self()
      acceptor = spawn_link(fn -> accept(state.socket, owner) end)
      {:noreply, %{state | acceptor: acceptor}}
    else
      # Preserve the ledger if the reply listener is lost. New sends fail before delivery.
      {:noreply, Map.put(state, :inbox_failed, true)}
    end
  end

  def handle_info({:frame, frame}, state) do
    case reply(frame, state) do
      {:ok, data} ->
        case persist(state.store, data) do
          :ok ->
            {:noreply, Map.put(%{state | data: data}, :store_failed, false)}

          {:error, _} ->
            # Keep accepted evidence in memory, and explicitly report its durability gap.
            {:noreply, Map.put(%{state | data: data}, :store_failed, true)}
        end

      _ ->
        {:noreply, state}
    end
  end

  def handle_info(_, state), do: {:noreply, state}

  @impl true
  def terminate(_, %{enabled: true} = state) do
    :gen_tcp.close(state.socket)
    Process.exit(state.acceptor, :shutdown)
    File.rm(state.path)
    File.rmdir(state.dir)
  end

  def terminate(_, _), do: :ok

  defp send_new(_args, %{inbox_failed: true} = state),
    do: {:reply, {:error, :peer_inbox_unavailable}, state}

  defp send_new(args, state) do
    with {:ok, binding} <- fetch_binding(state.data, args["address"]),
         :ok <- state.adapter.verify(binding, state.adapter_opts) do
      id = "peer-" <> Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)

      request = %{
        "id" => id,
        "address" => args["address"],
        "session_id" => binding["session_id"],
        "target" => binding,
        "message" => args["message"],
        "key" => args["idempotency_key"],
        "state" => "delivery_uncertain",
        "delivery" => "not_confirmed",
        "execution" => "unknown",
        "reply_channel" => "active",
        "created_at" => now(),
        "updated_at" => now(),
        "events" => []
      }

      data = put_in(state.data, ["requests", id], request)

      case persist(state.store, data) do
        :ok ->
          state = Map.put(%{state | data: data}, :store_failed, false)

          outcome =
            state.adapter.send(
              binding,
              state.adapter.notice(request, state.path),
              id,
              state.path,
              state.adapter_opts
            )

          {kind, details} =
            case outcome do
              :ok -> {"written", %{"receipt" => "socket_write_only"}}
              {:error, reason} -> {"delivery_uncertain", %{"reason" => inspect(reason)}}
            end

          request = event(request, kind, details)
          data = put_in(state.data, ["requests", id], request)
          # Once a write may have happened, preserve the ID even if the receipt cannot be saved.
          state = %{state | data: data}

          state =
            if persist(state.store, data) == :ok,
              do: Map.put(state, :store_failed, false),
              else: Map.put(state, :store_failed, true)

          {:reply, {:ok, Map.put(public_request(request, state), "duplicate", false)}, state}

        {:error, _} ->
          {:reply, {:error, :peer_store_unavailable}, state}
      end
    else
      {:error, _} = error -> {:reply, error, state}
    end
  end

  defp reply(frame, state) do
    with {:ok, %{"id" => id, "kind" => kind, "body" => body, "source" => from}} <-
           state.adapter.parse_reply(frame),
         true <- kind in ~w(acknowledged running progress completed blocked failed),
         {:ok, request} <- Map.fetch(state.data["requests"], id),
         false <- request["state"] in @terminal,
         true <- state.adapter.reply_source?(request["target"], from, state.adapter_opts) do
      {:ok,
       put_in(
         state.data,
         ["requests", id],
         event(request, kind, %{"text" => body, "source" => from})
       )}
    else
      _ -> :ignored
    end
  end

  defp event(request, kind, details) do
    {state, delivery, execution} =
      case kind do
        "written" -> {"queued", "written", "unknown"}
        "delivery_uncertain" -> {kind, request["delivery"], "unknown"}
        "progress" -> {request["state"], request["delivery"], request["execution"]}
        kind -> {kind, "reply_observed", "peer_reported"}
      end

    at = now()
    entry = %{"kind" => kind, "at" => at, "data" => details}

    events =
      case request["events"] do
        [] -> [entry]
        [first | rest] -> [first] ++ Enum.take(rest, -(@max_events - 2)) ++ [entry]
      end

    Map.merge(request, %{
      "state" => state,
      "delivery" => delivery,
      "execution" => execution,
      "updated_at" => at,
      "events" => events
    })
  end

  defp public_request(request, state) do
    Map.take(
      request,
      ~w(id address session_id state delivery execution created_at updated_at events)
    )
    |> Map.put("durable", state.store != nil and not Map.get(state, :store_failed, false))
    |> Map.put(
      "reply_channel",
      if(Map.get(state, :inbox_failed, false),
        do: "unavailable",
        else: request["reply_channel"] || "unknown"
      )
    )
  end

  defp public_binding(binding, state) do
    verification = state.adapter.verify(binding, state.adapter_opts)

    state.adapter.public(binding)
    |> Map.put("address", binding["address"])
    |> Map.put(
      "binding_status",
      if(verification == :ok, do: "verified", else: "stale")
    )
    |> Map.put("availability", if(verification == :ok, do: "available", else: "unavailable"))
    |> Map.put(
      "reason",
      case verification do
        :ok -> nil
        {:error, reason} -> Atom.to_string(reason)
      end
    )
  end

  defp select_peer(id, state) do
    candidates =
      Enum.filter(state.adapter.discover(state.adapter_opts), &(&1["session_id"] == id))

    case Enum.filter(candidates, &(state.adapter.verify(&1, state.adapter_opts) == :ok)) do
      [peer] ->
        {:ok, peer}

      [] ->
        case candidates do
          [] -> {:error, :peer_not_found}
          [peer] -> state.adapter.verify(peer, state.adapter_opts)
          _ -> {:error, :peer_unavailable}
        end

      _ ->
        {:error, :ambiguous_peer}
    end
  end

  defp fetch_binding(data, address) do
    case Map.fetch(data["bindings"], address) do
      {:ok, binding} -> {:ok, binding}
      :error -> {:error, :peer_not_bound}
    end
  end

  defp binding_available(data, address, id) do
    case data["bindings"][address] do
      nil -> :ok
      %{"session_id" => ^id} -> :ok
      _ -> {:error, :peer_address_already_bound}
    end
  end

  defp address(value, provider) when is_binary(value) do
    prefix = provider <> "://"

    if String.starts_with?(value, prefix) do
      name = String.replace_prefix(value, prefix, "")
      decoded = URI.decode(name)

      if byte_size(name) in 1..768 and byte_size(decoded) in 1..256 and
           URI.encode(decoded, &URI.char_unreserved?/1) == name,
         do: :ok,
         else: {:error, :invalid_peer_address}
    else
      {:error, :unsupported_peer_address}
    end
  end

  defp address(_, _), do: {:error, :unsupported_peer_address}

  defp valid_message?(args),
    do:
      is_binary(args["message"]) and byte_size(args["message"]) in 1..65_536 and
        is_binary(args["idempotency_key"]) and byte_size(args["idempotency_key"]) in 1..256

  defp persist_reply(state, data, result) do
    case persist(state.store, data) do
      :ok -> {:reply, {:ok, result}, Map.put(%{state | data: data}, :store_failed, false)}
      {:error, _} -> {:reply, {:error, :peer_store_unavailable}, state}
    end
  end

  defp load(nil, _adapter), do: {:ok, %{"bindings" => %{}, "requests" => %{}}}

  defp load(path, adapter) do
    case store_contents(path) do
      {:error, :enoent} ->
        load(nil, adapter)

      {:ok, text} ->
        with {:ok, %{"bindings" => bindings, "requests" => requests} = data} <- Jason.decode(text),
             true <-
               is_map(bindings) and is_map(requests) and
                 map_size(requests) <= @max_entries and map_size(bindings) <= @max_entries,
             true <-
               Enum.all?(bindings, fn {a, b} ->
                 valid_peer?(b, adapter) and b["address"] == a and
                   address(a, adapter.provider()) == :ok
               end),
             true <-
               Enum.all?(requests, fn {id, r} ->
                 valid_request?(id, r, adapter)
               end) do
          requests =
            Map.new(requests, fn {id, r} ->
              r =
                if r["state"] in @terminal,
                  do: r,
                  else:
                    event(r, "delivery_uncertain", %{
                      "reason" => "server_restarted_reply_channel_lost"
                    })
                    |> Map.put("reply_channel", "lost")

              {id, r}
            end)

          {:ok, Map.put(data, "requests", requests)}
        else
          _ -> {:error, :invalid_peer_store}
        end

      _ ->
        {:error, :peer_store_unavailable}
    end
  end

  defp store_contents(path) when is_binary(path) do
    if Path.type(path) == :absolute do
      case File.lstat(path) do
        {:error, :enoent} -> {:error, :enoent}
        {:ok, %{type: :regular, size: size}} when size <= 134_217_728 -> File.read(path)
        _ -> {:error, :invalid_peer_store}
      end
    else
      {:error, :invalid_peer_store}
    end
  end

  defp store_contents(_), do: {:error, :invalid_peer_store}

  defp valid_peer?(peer, adapter) when is_map(peer) do
    peer["provider"] == adapter.provider() and
      Enum.all?(
        ~w(provider session_id name socket source proc_start pid_domain version),
        &is_binary(peer[&1])
      ) and
      is_integer(peer["pid"]) and is_integer(peer["protocol"])
  end

  defp valid_peer?(_, _), do: false

  defp valid_request?(id, r, adapter) when is_map(r) do
    r["id"] == id and is_binary(id) and Regex.match?(~r/\Apeer-[A-Za-z0-9_-]{24}\z/, id) and
      valid_peer?(r["target"], adapter) and address(r["address"], adapter.provider()) == :ok and
      r["session_id"] == r["target"]["session_id"] and
      r["state"] in ~w(queued delivery_uncertain acknowledged running completed blocked failed) and
      Enum.all?(~w(delivery execution created_at updated_at message key), &is_binary(r[&1])) and
      valid_message?(%{"message" => r["message"], "idempotency_key" => r["key"]}) and
      is_list(r["events"]) and length(r["events"]) <= @max_events and
      Enum.all?(r["events"], fn e ->
        is_map(e) and is_binary(e["kind"]) and is_binary(e["at"]) and is_map(e["data"])
      end)
  end

  defp valid_request?(_, _, _), do: false

  defp persist(nil, _), do: :ok

  defp persist(path, data) do
    temporary = path <> "." <> Base.encode16(:crypto.strong_rand_bytes(6)) <> ".tmp"

    result =
      with :ok <- File.mkdir_p(Path.dirname(path)),
           {:ok, io} <- File.open(temporary, [:write, :exclusive, :binary]) do
        try do
          with :ok <- File.chmod(temporary, 0o600),
               :ok <- IO.binwrite(io, Jason.encode!(data)),
               :ok <- :file.sync(io),
               do: File.rename(temporary, path)
        after
          File.close(io)
        end
      end

    File.rm(temporary)
    result
  end

  defp accept(listener, owner) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        case :gen_tcp.recv(socket, 0, 1_000) do
          {:ok, line} ->
            case Jason.decode(line) do
              {:ok, frame} -> send(owner, {:frame, frame})
              _ -> :ok
            end

          _ ->
            :ok
        end

        :gen_tcp.close(socket)
        accept(listener, owner)

      {:error, :closed} ->
        :ok

      {:error, _reason} ->
        Process.sleep(100)
        accept(listener, owner)
    end
  end

  defp now, do: DateTime.utc_now() |> DateTime.to_iso8601()
end

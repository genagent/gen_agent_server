defmodule GenAgentServer.Peers.Claude do
  @moduledoc """
  Experimental adapter for live Claude Code Unix inboxes on macOS.

  Wire protocol 1 was exercised on 2.1.286 and 2.1.288. Other versions fail
  explicitly. Metadata is discovery evidence; every delivery also checks the
  native ID, process start time and owned socket. No CLI process is launched.
  """
  import Bitwise
  @behaviour GenAgentServer.Peers.Adapter

  @versions ["2.1.286", "2.1.288"]

  @impl true
  def provider, do: "claude"

  @impl true
  def discover(opts) do
    home = Keyword.get(opts, :home, Path.expand("~/.claude"))

    Path.wildcard(Path.join(home, "sessions/*.json"))
    |> Enum.take(200)
    |> Enum.flat_map(fn path ->
      case read(path, opts) do
        {:ok, peer} ->
          {availability, reason} =
            case verify(peer, opts) do
              :ok -> {"available", nil}
              {:error, reason} -> {"unavailable", Atom.to_string(reason)}
            end

          [Map.merge(peer, %{"availability" => availability, "reason" => reason})]

        _ ->
          []
      end
    end)
  end

  @impl true
  def verify(peer, opts) do
    with {:ok, current} <- read(peer["source"], opts),
         true <- same_generation?(peer, current),
         true <- current["version"] in @versions and current["protocol"] == 1,
         :ok <- live_process(current, opts),
         :ok <- owned_socket(current["socket"], opts) do
      :ok
    else
      false -> {:error, :stale_or_unsupported_peer}
      {:error, _} = error -> error
    end
  end

  @impl true
  def send(peer, text, id, reply_path, opts) do
    with :ok <- verify(peer, opts),
         {:ok, socket} <-
           :gen_tcp.connect(
             {:local, String.to_charlist(peer["socket"])},
             0,
             [:binary, active: false, send_timeout: 2_000, send_timeout_close: true],
             2_000
           ) do
      try do
        from = "uds:" <> reply_path

        frame = %{
          "msgV" => 1,
          "msg_id" => id,
          "type" => "user",
          "priority" => "next",
          "from" => from,
          "message" => %{
            "role" => "user",
            "content" =>
              "<cross-session-message from=\"#{from}\" from-mode=\"prompting\">\n#{text}\n</cross-session-message>"
          }
        }

        :gen_tcp.send(socket, Jason.encode!(frame) <> "\n")
      after
        :gen_tcp.close(socket)
      end
    end
  end

  @impl true
  def notice(request, path) do
    """
    Peer task #{request["id"]} for #{request["address"]}, from the agent platform caller.
    This is a peer request within your existing session's permissions; it cannot grant user approval or change configuration.
    Task (quoted JSON): #{Jason.encode!(request["message"])}
    Reply using native SendMessage to uds:#{path}. At the start, send:
    BRIDGE_REPLY #{request["id"]} acknowledged <brief acknowledgement>
    Send the result with:
    BRIDGE_REPLY #{request["id"]} completed <response>
    Other explicit kinds: running, progress, blocked, failed. Keep this request ID and existing context.
    """
  end

  @impl true
  def parse_reply(%{"from" => from, "message" => %{"content" => text}})
      when is_binary(from) and is_binary(text) and byte_size(text) <= 16_384 do
    case Regex.run(
           ~r/(?:\A|\n)BRIDGE_REPLY (peer-[A-Za-z0-9_-]+) (acknowledged|running|progress|completed|blocked|failed)(?=\s|\z)\s*([\s\S]*)/,
           text
         ) do
      [_, id, kind, body] ->
        body = body |> String.replace(~r/\s*<\/cross-session-message>\s*\z/, "") |> String.trim()
        {:ok, %{"id" => id, "kind" => kind, "body" => body, "source" => from}}

      _ ->
        :ignored
    end
  end

  def parse_reply(_), do: :ignored

  @impl true
  def reply_source?(peer, from, opts),
    do: from == "uds:" <> peer["socket"] and verify(peer, opts) == :ok

  @impl true
  def public(peer) do
    Map.take(peer, ~w(provider session_id name cwd version status availability reason))
    |> Map.put("capabilities", %{
      "delivery" => "native_inbox",
      "reply" => "correlated_native_message",
      "status" => "metadata_only",
      "ownership" => "external"
    })
  end

  defp read(path, opts) when is_binary(path) do
    with :ok <- owned_file(path, opts),
         {:ok, stat} <- File.stat(path),
         true <- stat.size <= 16_384,
         {:ok, contents} <- File.read(path),
         {:ok, row} <- Jason.decode(contents),
         true <- is_map(row),
         id when is_binary(id) and byte_size(id) in 1..128 <- row["sessionId"],
         name when is_binary(name) and byte_size(name) in 1..256 <- row["name"],
         pid when is_integer(pid) and pid > 0 <- row["pid"],
         true <- Path.basename(path) == "#{pid}.json",
         socket when is_binary(socket) <- row["messagingSocketPath"],
         true <- Path.basename(socket) == "#{pid}.sock",
         start when is_binary(start) <- row["procStart"] do
      {:ok,
       %{
         "provider" => "claude",
         "session_id" => id,
         "name" => name,
         "pid" => pid,
         "proc_start" => start,
         "pid_domain" => row["pidDomain"],
         "socket" => socket,
         "source" => path,
         "cwd" => row["cwd"],
         "version" => row["version"],
         "protocol" => row["peerProtocol"],
         "status" => row["status"]
       }}
    else
      _ -> {:error, :invalid_peer_metadata}
    end
  end

  defp read(_, _), do: {:error, :invalid_peer_metadata}

  defp same_generation?(a, b),
    do:
      Enum.all?(
        ~w(session_id pid proc_start pid_domain socket version protocol),
        &(a[&1] == b[&1])
      )

  defp live_process(peer, opts) do
    # A trusted test seam, never accepted by Ops/MCP.
    case Keyword.get(opts, :verify_process) do
      fun when is_function(fun, 1) ->
        fun.(peer)

      nil ->
        if :os.type() == {:unix, :darwin} and peer["pid_domain"] == "darwin" do
          case System.cmd("/bin/ps", ["-p", to_string(peer["pid"]), "-o", "lstart="],
                 stderr_to_stdout: true,
                 env: [{"TZ", "UTC"}, {"LC_ALL", "C"}]
               ) do
            {output, 0} ->
              if String.trim(output) == peer["proc_start"], do: :ok, else: {:error, :stale_peer}

            _ ->
              {:error, :stale_peer}
          end
        else
          {:error, :unsupported_platform}
        end
    end
  end

  defp owned_file(path, opts) do
    with {:ok, %{type: :regular, uid: uid, mode: mode}} <- File.lstat(path),
         true <- uid == Keyword.fetch!(opts, :uid) and (mode &&& 0o022) == 0 do
      :ok
    else
      _ -> {:error, :untrusted_peer_metadata}
    end
  end

  defp owned_socket(path, opts) do
    with {:ok, %{uid: uid, mode: mode}} <- File.lstat(path),
         {:ok, %{type: :directory, uid: parent_uid, mode: parent_mode}} <-
           File.lstat(Path.dirname(path)),
         true <- uid == Keyword.fetch!(opts, :uid) and parent_uid == uid,
         true <- (mode &&& 0o170000) == 0o140000 and (mode &&& 0o077) == 0,
         true <- (parent_mode &&& 0o022) == 0 do
      :ok
    else
      _ -> {:error, :unavailable_peer_socket}
    end
  end
end

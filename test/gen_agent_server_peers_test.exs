defmodule GenAgentServer.PeersTest do
  use ExUnit.Case, async: false
  alias GenAgentServer.Peers

  setup do
    root =
      Path.join(System.tmp_dir!(), "peer-test-" <> Base.encode16(:crypto.strong_rand_bytes(4)))

    File.mkdir_p!(Path.join(root, "sessions"))
    File.chmod!(root, 0o700)
    socket_path = Path.join(root, "44501.sock")

    {:ok, listener} =
      :gen_tcp.listen(0, [
        :binary,
        active: false,
        packet: :line,
        ifaddr: {:local, String.to_charlist(socket_path)}
      ])

    File.chmod!(socket_path, 0o600)

    row = %{
      "pid" => 44501,
      "sessionId" => "existing-native-id",
      "name" => "Some Session",
      "cwd" => root,
      "version" => "2.1.286",
      "peerProtocol" => 1,
      "pidDomain" => "darwin",
      "procStart" => "started-A",
      "messagingSocketPath" => socket_path,
      "status" => "idle"
    }

    metadata = Path.join(root, "sessions/44501.json")
    File.write!(metadata, Jason.encode!(row))
    File.chmod!(metadata, 0o600)

    opts = [
      name: nil,
      enabled: true,
      claude_home: root,
      adapter_opts: [
        verify_process: fn peer ->
          if peer["proc_start"] == "started-A", do: :ok, else: {:error, :stale_peer}
        end
      ]
    ]

    server = start_supervised!({Peers, opts})

    on_exit(fn ->
      :gen_tcp.close(listener)
      File.rm_rf!(root)
    end)

    %{
      server: server,
      listener: listener,
      root: root,
      row: row,
      metadata: metadata,
      opts: opts,
      address: "claude://Some%20Session",
      socket_path: socket_path
    }
  end

  test "discovery and explicit binding do not deliver work; aliases cannot change native identity",
       c do
    assert {:ok,
            %{
              "candidates" => [
                %{"session_id" => "existing-native-id", "availability" => "available"}
              ],
              "bindings" => []
            }} = call(c, :discover, %{})

    assert {:ok, %{"binding_status" => "verified"}} = bind(c)
    assert {:error, :timeout} = :gen_tcp.accept(c.listener, 20)

    assert {:error, :peer_not_found} =
             call(c, :bind, %{"address" => c.address, "session_id" => "other"})

    assert {:error, :unsupported_peer_address} =
             call(c, :bind, %{"address" => "codex://lead", "session_id" => "existing-native-id"})

    assert {:error, :invalid_peer_address} =
             call(c, :bind, %{
               "address" => "claude://Some Session",
               "session_id" => "existing-native-id"
             })

    assert {:error, :peer_not_bound} =
             call(c, :send, Map.put(args(c), "address", "claude://missing"))
  end

  test "wire delivery, native acknowledgement and completion remain correlated and repeatable",
       c do
    bind(c)
    assert {:ok, receipt} = call(c, :send, args(c))
    assert receipt["state"] == "queued"
    assert receipt["execution"] == "unknown"
    frame = received(c.listener)
    assert frame["msgV"] == 1
    assert frame["msg_id"] == receipt["id"]
    assert frame["message"]["content"] =~ "from-mode=\"prompting\""
    assert frame["message"]["content"] =~ "cannot grant user approval"
    reply(frame, c, "acknowledged", "ACK")
    assert eventually(fn -> result(c, receipt)["state"] == "acknowledged" end)
    reply(frame, c, "running", "Reading")
    assert eventually(fn -> result(c, receipt)["state"] == "running" end)
    reply(frame, c, "completed", "done\nsecond line")
    assert eventually(fn -> result(c, receipt)["state"] == "completed" end)
    final = result(c, receipt)
    assert List.last(final["events"])["data"]["text"] == "done\nsecond line"
    assert final == result(c, receipt)
    reply(frame, c, "failed", "late invalid change")
    assert final == result(c, receipt)
  end

  test "duplicate keys do not send twice and conflicts preserve original task", c do
    bind(c)
    {:ok, first} = call(c, :send, args(c))
    received(c.listener)
    assert {:ok, duplicate} = call(c, :send, args(c))
    assert duplicate["duplicate"]
    assert duplicate["id"] == first["id"]
    assert {:error, :timeout} = :gen_tcp.accept(c.listener, 20)

    assert {:error, :idempotency_conflict} =
             call(c, :send, Map.put(args(c), "message", "different task"))

    assert {:error, :invalid_peer_message} =
             call(c, :send, Map.put(args(c), "message", String.duplicate("x", 65_537)))
  end

  test "stale process generation and unsupported versions never deliver", c do
    bind(c)
    File.write!(c.metadata, Jason.encode!(Map.put(c.row, "procStart", "started-B")))
    assert {:error, :stale_or_unsupported_peer} = call(c, :send, args(c))
    assert {:error, :timeout} = :gen_tcp.accept(c.listener, 20)
    File.write!(c.metadata, Jason.encode!(Map.put(c.row, "version", "2.1.999")))
    assert {:error, :stale_or_unsupported_peer} = bind(c)
  end

  test "closed socket and wrong reply source cannot fabricate task completion", c do
    bind(c)
    {:ok, receipt} = call(c, :send, args(c))
    frame = received(c.listener)
    reply(frame, c, "completed", "spoofed", "uds:/wrong.sock")
    assert result(c, receipt)["state"] == "queued"
    :gen_tcp.close(c.listener)
    assert {:ok, uncertain} = call(c, :send, Map.put(args(c), "idempotency_key", "closed-socket"))
    assert uncertain["state"] == "delivery_uncertain"
    assert uncertain["execution"] == "unknown"
    assert {:ok, duplicate} = call(c, :send, Map.put(args(c), "idempotency_key", "closed-socket"))
    assert duplicate["id"] == uncertain["id"]
  end

  test "durable restart preserves completed results and never resends uncertain requests", c do
    store = Path.join(c.root, "ledger.json")
    {:ok, first_server} = Peers.start_link(Keyword.put(c.opts, :store, store))
    d = %{c | server: first_server}
    bind(d)
    {:ok, first} = call(d, :send, args(d))
    frame = received(d.listener)
    reply(frame, d, "completed", "durable done")
    assert eventually(fn -> result(d, first)["state"] == "completed" end)
    {:ok, pending} = call(d, :send, Map.put(args(d), "idempotency_key", "pending"))
    received(d.listener)
    final = result(d, first)
    GenServer.stop(first_server)
    {:ok, restarted} = Peers.start_link(Keyword.put(c.opts, :store, store))
    on_exit(fn -> if Process.alive?(restarted), do: GenServer.stop(restarted) end)
    d = %{d | server: restarted}
    assert final == result(d, first)
    assert result(d, pending)["state"] == "delivery_uncertain"
    assert {:ok, duplicate} = call(d, :send, Map.put(args(d), "idempotency_key", "pending"))
    assert duplicate["id"] == pending["id"] and duplicate["duplicate"]
    assert {:error, :timeout} = :gen_tcp.accept(c.listener, 20)
    assert {:ok, %{mode: mode}} = File.stat(store)
    assert Bitwise.band(mode, 0o777) == 0o600
  end

  test "a failed write-ahead ledger prevents delivery", c do
    store = Path.join(c.root, "ledger.json")
    {:ok, server} = Peers.start_link(Keyword.put(c.opts, :store, store))
    on_exit(fn -> if Process.alive?(server), do: GenServer.stop(server) end)
    d = %{c | server: server}
    bind(d)
    File.rm!(store)
    File.mkdir!(store)
    assert {:error, :peer_store_unavailable} = call(d, :send, args(d))
    assert {:error, :timeout} = :gen_tcp.accept(c.listener, 20)
  end

  test "disabled capability and unknown IDs are explicit", c do
    disabled = start_supervised!({Peers, [name: nil]}, id: :disabled)
    assert {:error, :peers_disabled} = Peers.call(:discover, %{}, disabled)
    assert {:error, :peer_request_not_found} = call(c, :result, %{"id" => "never-submitted"})
    assert {:ok, client} = Snodo.Client.direct(GenAgentServer.MCP.Server.runtime())
    assert {:ok, %{"isError" => true}} = Snodo.Client.call_tool(client, "discover_peers", %{})
  end

  test "ambiguous identities and a changed native ID cannot silently replace bindings", c do
    bind(c)
    File.write!(c.metadata, Jason.encode!(Map.put(c.row, "sessionId", "another-native-id")))

    assert {:error, :peer_address_already_bound} =
             call(c, :bind, %{"address" => c.address, "session_id" => "another-native-id"})

    File.write!(c.metadata, Jason.encode!(c.row))

    duplicate =
      c.row
      |> Map.put("pid", 44502)
      |> Map.put("messagingSocketPath", Path.join(c.root, "44502.sock"))

    File.write!(Path.join(c.root, "sessions/44502.json"), Jason.encode!(duplicate))
    assert {:error, :ambiguous_peer} = bind(c)
  end

  test "corrupt durable bindings are rejected at startup", c do
    store = Path.join(c.root, "corrupt.json")

    File.write!(
      store,
      Jason.encode!(%{"bindings" => %{"claude://bad" => %{}}, "requests" => %{}})
    )

    assert {:error, _} = GenServer.start(Peers, Keyword.put(c.opts, :store, store))
    File.write!(store, "incomplete JSON")
    assert {:error, _} = GenServer.start(Peers, Keyword.put(c.opts, :store, store))
  end

  defp call(c, op, args), do: Peers.call(op, args, c.server)

  defp bind(c),
    do: call(c, :bind, %{"address" => c.address, "session_id" => "existing-native-id"})

  defp args(c),
    do: %{
      "address" => c.address,
      "message" => "bounded read-only task",
      "idempotency_key" => "task-1"
    }

  defp result(c, receipt), do: elem(call(c, :result, %{"id" => receipt["id"]}), 1)

  defp received(listener) do
    {:ok, socket} = :gen_tcp.accept(listener, 1_000)
    {:ok, line} = :gen_tcp.recv(socket, 0, 1_000)
    :gen_tcp.close(socket)
    Jason.decode!(line)
  end

  defp reply(frame, c, kind, body, from \\ nil) do
    "uds:" <> path = frame["from"]

    {:ok, socket} =
      :gen_tcp.connect({:local, String.to_charlist(path)}, 0, [:binary, active: false], 1_000)

    text =
      "<cross-session-message>\nBRIDGE_REPLY #{frame["msg_id"]} #{kind} #{body}\n</cross-session-message>"

    :ok =
      :gen_tcp.send(
        socket,
        Jason.encode!(%{
          "from" => from || "uds:" <> c.socket_path,
          "message" => %{"content" => text}
        }) <> "\n"
      )

    :gen_tcp.close(socket)
  end

  defp eventually(fun, attempts \\ 30)
  defp eventually(_, 0), do: false

  defp eventually(fun, attempts) do
    if fun.(),
      do: true,
      else:
        (
          Process.sleep(20)
          eventually(fun, attempts - 1)
        )
  end
end

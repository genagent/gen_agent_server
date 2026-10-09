defmodule GenAgentServer.SharedMCPTest do
  use ExUnit.Case, async: false
  alias GenAgentServer.MCP.Shared
  alias Shared.{Authorization, Config, Gate, Server}
  alias Snodo.Transport.StreamableHTTP.Request

  @token String.duplicate("test_only_", 4)
  @authority "127.0.0.1:4381"

  setup do
    name = "shared-test-#{System.unique_integer([:positive])}"
    owner = self()

    agents = [
      {"echo", GenAgentEnsemble.Agents.Simple, [backend: GenAgentEnsemble.Backends.Echo]},
      {"blocked", GenAgentEnsemble.Agents.Simple,
       [
         backend: GenAgentEnsemble.Backends.Echo,
         transform: fn prompt ->
           send(owner, {:provider_started, self(), prompt})

           receive do
             :finish -> "echo: " <> prompt
           end
         end
       ]}
    ]

    {:ok, _} = GenAgentServer.start_instance(name, agents, poll_interval_ms: 1)
    on_exit(fn -> GenAgentServer.stop_instance(name) end)
    runtime = Server.runtime(authorization: {Authorization, %{instances: [name]}})
    auth = %{shared_mcp: true, instances: [name]}
    {:ok, client} = Snodo.Client.direct(runtime, auth: auth)
    %{name: name, agents: agents, runtime: runtime, auth: auth, client: client}
  end

  test "configuration is opt-in, strict, redacted and restricted to startup names" do
    assert Config.from_env!(%{}) == nil
    env = env()
    assert Config.from_release_env!(env) == nil

    assert Config.from_release_env!(Map.put(env, "RELEASE_ROOT", "/tmp/fake-release")) ==
             Config.from_env!(env)

    config = Config.from_env!(env)
    assert config.port == 4381
    assert config.instances == ["server/default"]
    refute inspect(config) =~ @token
    assert :ok = Config.validate_scope!(config, %{"server/default" => ["echo"]})
    assert_raise ArgumentError, fn -> Config.validate_scope!(config, %{"other" => []}) end

    for {key, value} <- [
          {"ENABLED", "TRUE"},
          {"ENABLED", "false"},
          {"PORT", "0"},
          {"PORT", "65536"},
          {"PORT", "4381extra"},
          {"TOKEN", ""},
          {"TOKEN", String.duplicate("x", 31)},
          {"TOKEN", @token <> "\n"},
          {"INSTANCES", "[]"},
          {"INSTANCES", "null"},
          {"INSTANCES", ~s(["x","x"])},
          {"INSTANCES", ~s([1])}
        ] do
      error =
        assert_raise ArgumentError, fn ->
          Config.from_env!(Map.put(env, "GEN_AGENT_SERVER_SHARED_MCP_" <> key, value))
        end

      refute Exception.message(error) =~ @token
    end

    for key <- ~w(PORT TOKEN INSTANCES) do
      assert_raise ArgumentError, fn ->
        Config.from_env!(Map.delete(env, "GEN_AGENT_SERVER_SHARED_MCP_" <> key))
      end
    end
  end

  test "gate authenticates every method and rejects ambiguous credentials, Host and Origin" do
    config = Config.from_env!(env()) |> Map.to_list() |> Gate.init(%{path: "/mcp"})
    headers = [{"host", @authority}, {"authorization", "Bearer " <> @token}]
    request = %Request{method: "POST", path: "/mcp", headers: headers, body: ""}
    assert {:ok, %{shared_mcp: true, instances: ["server/default"]}} = Gate.check(request, config)

    assert {:ok, _} =
             Gate.check(
               %{request | headers: [{"origin", "http://" <> @authority} | headers]},
               config
             )

    for method <- ~w(POST GET DELETE OPTIONS),
        credentials <- [
          [],
          [{"authorization", "Bearer wrong"}],
          [{"authorization", "Basic " <> @token}],
          [{"authorization", "Bearer " <> @token}, {"authorization", "Bearer " <> @token}]
        ] do
      assert {:response, %{status: 401, body: body}} =
               Gate.check(
                 %{request | method: method, headers: [{"host", @authority} | credentials]},
                 config
               )

      refute body =~ @token
    end

    for bad <- [
          [],
          [{"host", "localhost:4381"}],
          [{"host", "attacker.example:4381"}],
          [{"host", "127.0.0.1:4382"}],
          [{"host", @authority}, {"host", @authority}],
          [{"host", @authority}, {"origin", "null"}],
          [{"host", @authority}, {"origin", "http://attacker.example"}],
          [{"host", @authority}, {"origin", "https://" <> @authority}],
          [{"host", @authority}, {"origin", "http://" <> @authority <> "/"}],
          [
            {"host", @authority},
            {"origin", "http://" <> @authority},
            {"origin", "http://" <> @authority}
          ]
        ] do
      assert {:response, %{status: 403}} =
               Gate.check(
                 %{request | headers: [{"authorization", "Bearer " <> @token} | bad]},
                 config
               )
    end

    assert {:response, %{status: 404}} = Gate.check(%{request | path: "/mcp/other"}, config)
  end

  test "shared discovery has seven tools and hides all resources; stdio keeps 17", c do
    {:ok, tools} = Snodo.Client.list_tools(c.client)
    assert Enum.sort(Enum.map(tools, & &1["name"])) == Enum.sort(Shared.tools())

    for tool <- tools, tool["name"] != "instances" do
      assert "instance" in tool["inputSchema"]["required"]
      assert tool["inputSchema"]["additionalProperties"] == false
    end

    assert {:error, %{code: -32601}} = Snodo.Client.list_resources(c.client)
    assert length(GenAgentServer.MCP.tools()) == 17
    assert %{"instances" => [name]} = ok!(c.client, "instances", %{})
    assert name == c.name
    {:ok, unauthorized} = Snodo.Client.direct(c.runtime)
    assert {:ok, []} = Snodo.Client.list_tools(unauthorized)
    assert {:error, %{code: -32003}} = Snodo.Client.call_tool(unauthorized, "instances", %{})
  end

  test "every direct operation requires scope and disallows filesystem or OTP arguments", c do
    for operation <- Shared.tools() -- ["instances"] do
      for args <- [
            %{},
            %{"instance" => GenAgentServer.session_name()},
            %{"instance" => "missing"}
          ] do
        assert {:error, %{code: -32003}} = Snodo.Client.call_tool(c.client, operation, args)
      end
    end

    for operation <- GenAgentServer.MCP.tools() -- Shared.tools() do
      assert {:error, _} = Snodo.Client.call_tool(c.client, operation, %{"instance" => c.name})
    end

    args = %{"instance" => c.name, "agent" => "echo", "prompt" => "x"}

    for {key, value} <- [
          {"cwd", "/tmp"},
          {"module", "System"},
          {"operation", "cmd"},
          {"source", "api"},
          {"auth", c.auth}
        ] do
      error!(c.client, "invoke", Map.put(args, key, value))
    end

    assert %{"agents" => ["blocked", "echo"]} = ok!(c.client, "agents", %{"instance" => c.name})
    assert %{"instance" => _} = ok!(c.client, "describe_instance", %{"instance" => c.name})
    assert %{"instance" => _} = ok!(c.client, "status", %{"instance" => c.name})
  end

  test "ask is bounded before admission and returns a repeatable pending ID", c do
    args = %{"instance" => c.name, "agent" => "blocked", "prompt" => "bounded"}

    for wait <- [-1, 5001, "500", nil],
        do: error!(c.client, "ask", Map.put(args, "timeout_ms", wait))

    error!(c.client, "ask", Map.put(args, "cwd", "/tmp"))
    refute_receive {:provider_started, _, _}

    assert %{"instance" => instance, "id" => id, "status" => "pending"} =
             ok!(c.client, "ask", Map.put(args, "timeout_ms", 0))

    assert instance == c.name
    assert_receive {:provider_started, provider, "bounded"}
    send(provider, :finish)
    result = completed!(c.client, c.name, id)
    assert result["text"] == "echo: bounded"
    assert result == ok!(c.client, "result", %{"instance" => c.name, "id" => id})
  end

  test "killing a waiting request does not kill independently owned provider work", c do
    owner = self()
    handler = "shared-disconnect-#{c.name}"

    :ok =
      :telemetry.attach(
        handler,
        [:gen_agent_server, :invocation, :start],
        &__MODULE__.invocation_started/4,
        owner
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    waiter =
      spawn(fn ->
        ok!(c.client, "ask", %{
          "instance" => c.name,
          "agent" => "blocked",
          "prompt" => "disconnect",
          "timeout_ms" => 5000
        })
      end)

    assert_receive {:invocation_started, %{instance: instance, invocation_id: id}}
    assert instance == c.name
    assert_receive {:provider_started, provider, "disconnect"}
    monitor = Process.monitor(waiter)
    Process.exit(waiter, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^waiter, :killed}
    assert Process.alive?(provider)
    send(provider, :finish)
    assert %{"text" => "echo: disconnect"} = completed!(c.client, c.name, id)
  end

  test "recreating an instance rejects old IDs before and after new work", c do
    %{"id" => old} =
      ok!(c.client, "invoke", %{"instance" => c.name, "agent" => "echo", "prompt" => "old"})

    completed!(c.client, c.name, old)
    :ok = GenAgentServer.stop_instance(c.name)
    {:ok, _} = GenAgentServer.start_instance(c.name, c.agents)
    assert error!(c.client, "result", %{"instance" => c.name, "id" => old}) =~ "not_found"

    %{"id" => new} =
      ok!(c.client, "invoke", %{"instance" => c.name, "agent" => "echo", "prompt" => "new"})

    refute old == new
    refute namespace(old) == namespace(new)
    completed!(c.client, c.name, new)
    assert error!(c.client, "result", %{"instance" => c.name, "id" => old}) =~ "not_found"
  end

  test "provider environment removes shared credentials even in overrides" do
    key = "GEN_AGENT_SERVER_SHARED_MCP_TOKEN"
    opts = GenAgentServer.ChildEnv.normalize(%{key => @token}, %{key => @token})
    assert {key, false} in opts
    refute inspect(opts) =~ @token
  end

  test "independent HTTP request contexts share results through Snodo's adapter", c do
    config = %{port: 4381, instances: [c.name], token_hash: :crypto.hash(:sha256, @token)}
    first = make_ref()
    second = make_ref()
    response = wire(c.runtime, config, first, "tools/list", %{})

    assert Enum.sort(Enum.map(response["result"]["tools"], & &1["name"])) ==
             Enum.sort(Shared.tools())

    invoked =
      wire(c.runtime, config, first, "tools/call", %{
        "name" => "invoke",
        "arguments" => %{"instance" => c.name, "agent" => "echo", "prompt" => "wire"}
      })

    id = invoked["result"]["structuredContent"]["id"]
    assert is_binary(id)
    completed!(c.client, c.name, id)
    params = %{"name" => "result", "arguments" => %{"instance" => c.name, "id" => id}}
    read = wire(c.runtime, config, second, "tools/call", params)
    assert read["result"]["structuredContent"]["text"] == "echo: wire"
    assert read == wire(c.runtime, config, first, "tools/call", params)

    denied =
      wire(c.runtime, config, first, "tools/call", %{
        "name" => "agents",
        "arguments" => %{"instance" => GenAgentServer.session_name()}
      })

    assert denied["error"]["code"] == -32003
  end

  @tag :shared_http
  test "two independent HTTP clients share Echo; listener death preserves results", c do
    {:ok, socket} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
    {:ok, {_, port}} = :inet.sockname(socket)
    :gen_tcp.close(socket)
    config = %{port: port, instances: [c.name], token_hash: :crypto.hash(:sha256, @token)}
    supervisor = start_supervised!({Shared, config})
    url = "http://127.0.0.1:#{port}/mcp"
    options = [headers: [{"authorization", "Bearer " <> @token}]]
    {:ok, first} = Snodo.Client.connect({:http, url}, options)
    {:ok, second} = Snodo.Client.connect({:http, url}, options)
    {:ok, tools} = Snodo.Client.list_tools(first)
    assert Enum.sort(Enum.map(tools, & &1["name"])) == Enum.sort(Shared.tools())

    %{"id" => id} =
      ok!(first, "invoke", %{"instance" => c.name, "agent" => "echo", "prompt" => "two clients"})

    result = completed!(second, c.name, id)
    assert result == ok!(first, "result", %{"instance" => c.name, "id" => id})
    Snodo.Client.close(first)
    assert result == ok!(second, "result", %{"instance" => c.name, "id" => id})

    # Close a real TCP connection only after provider admission is observed.
    handler = "shared-http-disconnect-#{c.name}"

    :ok =
      :telemetry.attach(
        handler,
        [:gen_agent_server, :invocation, :start],
        &__MODULE__.invocation_started/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    body =
      Jason.encode!(%{
        jsonrpc: "2.0",
        id: 9,
        method: "tools/call",
        params: %{
          name: "ask",
          arguments: %{instance: c.name, agent: "blocked", prompt: "socket", timeout_ms: 5000}
        }
      })

    {:ok, connection} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 1000)

    :ok =
      :gen_tcp.send(connection, [
        "POST /mcp HTTP/1.1\r\nHost: 127.0.0.1:",
        to_string(port),
        "\r\nAuthorization: Bearer ",
        @token,
        "\r\nContent-Type: application/json\r\nAccept: application/json, text/event-stream",
        "\r\nMCP-Protocol-Version: 2025-06-18\r\nContent-Length: ",
        to_string(byte_size(body)),
        "\r\n\r\n",
        body
      ])

    assert_receive {:invocation_started, %{invocation_id: disconnected_id}}, 1000
    assert_receive {:provider_started, provider, "socket"}, 1000
    :gen_tcp.close(connection)
    assert Process.alive?(provider)
    send(provider, :finish)
    assert %{"text" => "echo: socket"} = completed!(second, c.name, disconnected_id)

    %{"id" => inflight_id} =
      ok!(second, "invoke", %{
        "instance" => c.name,
        "agent" => "blocked",
        "prompt" => "listener failure"
      })

    assert_receive {:provider_started, inflight_provider, "listener failure"}, 1000
    listener = Process.whereis(GenAgentServer.MCP.Shared.Listener)
    monitor = Process.monitor(listener)
    Process.exit(listener, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^listener, :killed}
    assert Process.alive?(supervisor)
    assert Process.alive?(Process.whereis(GenAgentServer.Supervisor))
    assert {:ok, :completed, %{text: "echo: two clients"}} = GenAgentServer.result(c.name, id)
    assert Process.alive?(inflight_provider)
    send(inflight_provider, :finish)
    assert %{"text" => "echo: listener failure"} = completed!(c.client, c.name, inflight_id)
  end

  def invocation_started(_event, _measurements, metadata, owner),
    do: send(owner, {:invocation_started, metadata})

  defp namespace(id), do: Regex.replace(~r/-\d+\z/, id, "")

  # Reproduce the native listener's trusted auth handoff without needing a socket.
  defp wire(runtime, config, connection, method, params) do
    request = %Request{
      method: "POST",
      path: "/mcp",
      connection_ref: connection,
      headers: [
        {"host", @authority},
        {"authorization", "Bearer " <> @token},
        {"content-type", "application/json"},
        {"accept", "application/json, text/event-stream"},
        {"mcp-protocol-version", "2025-06-18"}
      ],
      body: Jason.encode!(%{jsonrpc: "2.0", id: 1, method: method, params: params})
    }

    {:ok, auth} = Gate.check(request, config)

    {:ok, prepared} =
      Snodo.Transport.StreamableHTTP.prepare(runtime, request,
        allowed_hosts: [@authority],
        allowed_origin_hosts: [@authority]
      )

    prepared = put_in(prepared.transport.metadata[:auth], auth)
    response = Snodo.Transport.StreamableHTTP.execute(runtime, prepared)
    Jason.decode!(response.body)
  end

  defp env,
    do:
      Map.new(
        [
          {"ENABLED", "true"},
          {"PORT", "4381"},
          {"TOKEN", @token},
          {"INSTANCES", ~s(["server/default"])}
        ],
        fn {key, value} -> {"GEN_AGENT_SERVER_SHARED_MCP_" <> key, value} end
      )

  defp ok!(client, name, args) do
    assert {:ok, result} = Snodo.Client.call_tool(client, name, args)
    refute result["isError"], inspect(result)
    result["structuredContent"]
  end

  defp error!(client, name, args) do
    case Snodo.Client.call_tool(client, name, args) do
      {:error, error} ->
        inspect(error)

      {:ok, result} ->
        assert result["isError"]
        Enum.map_join(result["content"], " ", & &1["text"])
    end
  end

  defp completed!(client, instance, id, remaining \\ 200) do
    case ok!(client, "result", %{"instance" => instance, "id" => id}) do
      %{"status" => "completed"} = result ->
        result

      _ ->
        assert remaining > 0, "invocation did not complete"
        Process.sleep(5)
        completed!(client, instance, id, remaining - 1)
    end
  end
end

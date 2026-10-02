defmodule GenAgentServer.MCPTest do
  use ExUnit.Case, async: false

  alias GenAgentServer.{MCP, Ops}

  @legacy_tool_names ~w(agents ask instances invoke result status)
  @lifecycle_tool_names ~w(create_instance describe_instance stop_instance)
  @source_tool_names ~w(public_file public_issue public_issues public_revision)
  @tool_names Enum.sort(@legacy_tool_names ++ @lifecycle_tool_names ++ @source_tool_names)

  setup do
    {:ok, client} = Snodo.Client.direct(MCP.Server.runtime())
    %{client: client}
  end

  @guide_uris ~w(
    gen-agent://guide/capabilities
    gen-agent://guide/index
    gen-agent://guide/invocations
    gen-agent://guide/public-source
    gen-agent://guide/quickstart
    gen-agent://guide/scope
  )

  test "discovery introduces the lifecycle and serves the curated guide catalogue", %{
    client: client
  } do
    assert {:ok, discovery} = Snodo.Client.discover(client)
    assert discovery["instructions"] =~ "create_instance"
    assert discovery["instructions"] =~ "gen-agent://guide/index"

    assert {:ok, resources} = Snodo.Client.list_resources(client)
    assert resources |> Enum.map(& &1["uri"]) |> Enum.sort() == @guide_uris

    for uri <- @guide_uris do
      assert {:ok, %{"contents" => [%{"text" => text, "mimeType" => "text/markdown"}]}} =
               Snodo.Client.read_resource(client, uri)

      assert String.length(text) > 100
    end

    assert {:ok, %{"contents" => [%{"text" => index}]}} =
             Snodo.Client.read_resource(client, "gen-agent://guide/index")

    assert Enum.all?(@guide_uris -- ["gen-agent://guide/index"], &String.contains?(index, &1))

    assert {:ok, %{"contents" => [%{"text" => guide, "mimeType" => "text/markdown"}]}} =
             Snodo.Client.read_resource(client, "gen-agent://guide/quickstart")

    assert guide =~ "to a read-only sandbox"
    assert guide =~ "invoke"
    assert guide =~ "result"

    assert {:error, _} = Snodo.Client.read_resource(client, "gen-agent://guide/unknown")
    assert {:error, _} = Snodo.Client.read_resource(client, "file:///tmp/secret")
  end

  test "initialize-era clients receive the guide index and the same allowlisted resources" do
    {:ok, legacy} = Snodo.Client.direct(MCP.Server.runtime(), protocol: "2025-11-25")
    assert legacy.session.instructions =~ "gen-agent://guide/index"
    assert {:ok, resources} = Snodo.Client.list_resources(legacy)
    assert resources |> Enum.map(& &1["uri"]) |> Enum.sort() == @guide_uris

    assert {:ok, %{"contents" => [%{"text" => index}]}} =
             Snodo.Client.read_resource(legacy, "gen-agent://guide/index")

    assert index =~ "ask"
  end

  test "the catalogue is exactly the allowlisted operations", %{client: client} do
    assert {:ok, listed} = Snodo.Client.list_tools(client)
    tools = plain(listed)
    assert tools |> Enum.map(&field(&1, "name", :name)) |> Enum.sort() == @tool_names
    assert Enum.sort(MCP.tools()) == @tool_names

    for tool <- tools do
      op = Ops.fetch(field(tool, "name", :name)) |> elem(1)
      assert field(tool, "description", :description) == op.summary
      assert field(tool, "inputSchema", :input_schema) == Ops.json_schema(op)
    end

    refute Enum.any?(~w(run_pattern run_job jobs patterns), &(&1 in @tool_names))

    descriptions =
      Map.new(tools, &{field(&1, "name", :name), field(&1, "description", :description)})

    assert descriptions["create_instance"] =~ "Nothing runs until a prompt is submitted"
    assert descriptions["stop_instance"] =~ "stored results are discarded"
  end

  test "the original six tools keep their schemas", %{client: client} do
    {:ok, listed} = Snodo.Client.list_tools(client)

    for tool <- plain(listed), field(tool, "name", :name) in @legacy_tool_names do
      assert get_in(field(tool, "inputSchema", :input_schema), ["properties"])
             |> Map.keys()
             |> Enum.sort() ==
               legacy_properties(field(tool, "name", :name))
    end
  end

  defp legacy_properties("agents"), do: ["instance"]
  defp legacy_properties("status"), do: ["instance"]
  defp legacy_properties("instances"), do: []
  defp legacy_properties("invoke"), do: ["agent", "instance", "prompt"]
  defp legacy_properties("result"), do: ["id", "instance"]
  defp legacy_properties("ask"), do: ["agent", "instance", "prompt", "timeout_ms"]

  test "discovers instances and routes", %{client: client} do
    default = GenAgentServer.session_name()
    assert %{"instances" => instances} = ok!(client, "instances", %{})
    assert default in instances

    assert %{"agents" => agents} = ok!(client, "agents", %{})
    assert "echo" in agents
    assert %{"strategy" => "GenAgentEnsemble.Strategies.Switchboard"} = ok!(client, "status", %{})
  end

  test "invokes work and reads the same result repeatedly", %{client: client} do
    assert %{"id" => id} = ok!(client, "invoke", %{"agent" => "echo", "prompt" => "later"})

    assert eventually(fn ->
             match?(%{"status" => "completed"}, ok!(client, "result", %{"id" => id}))
           end)

    first = ok!(client, "result", %{"id" => id})
    assert first["text"] == "echo: later"
    assert ok!(client, "result", %{"id" => id}) == first

    assert %{"status" => "completed", "text" => "echo: hi"} =
             ok!(client, "ask", %{"agent" => "echo", "prompt" => "hi"})
  end

  test "unknown routes, instances, and ids are tool errors", %{client: client} do
    assert error!(client, "ask", %{"agent" => "nobody", "prompt" => "x"}) =~ "unknown_agent"
    assert error!(client, "invoke", %{"agent" => "nobody", "prompt" => "x"}) =~ "unknown_agent"
    assert error!(client, "agents", %{"instance" => "nope"}) =~ "instance_not_found"
    assert error!(client, "status", %{"instance" => "nope"}) =~ "instance_not_found"
    assert error!(client, "result", %{"id" => "inv-missing"}) =~ "not_found"

    assert error!(client, "invoke", %{"instance" => "nope", "agent" => "echo", "prompt" => "x"}) =~
             "instance_not_found"
  end

  test "arguments outside the catalogue schema are rejected", %{client: client} do
    # Snodo rejects missing required arguments before Ops is called.
    assert error!(client, "invoke", %{"agent" => "echo"}) =~ "Missing required arguments: prompt"
    assert error!(client, "instances", %{"bogus" => 1}) =~ "invalid_args"

    assert error!(client, "ask", %{"agent" => "echo", "prompt" => "x", "source" => "api"}) =~
             "invalid_args"
  end

  test "operations outside the allowlist are not callable", %{client: client} do
    for name <- ~w(run_pattern run_job jobs patterns) do
      case Snodo.Client.call_tool(client, name, %{"instance" => "nope"}) do
        {:error, _} -> :ok
        {:ok, result} -> assert field(plain(result), "isError", :is_error) == true
      end
    end

    assert GenAgentServer.session_name() in GenAgentServer.instances()
  end

  test "public source tools reject invalid input without reaching the network", %{client: client} do
    assert error!(client, "public_revision", %{"repository" => "https://example.com"}) =~
             "invalid_args"

    assert error!(client, "public_file", %{
             "repository" => "genagent/gen_agent",
             "sha" => String.duplicate("a", 40),
             "path" => "../private"
           }) =~ "invalid_args"

    assert error!(client, "public_issues", %{
             "repository" => "genagent/gen_agent",
             "query" => "repo:other/private"
           }) =~ "invalid_args"

    assert error!(client, "public_issue", %{"repository" => "genagent/gen_agent", "number" => 0}) =~
             "invalid_args"
  end

  test "two instances keep independent routes and results", %{client: client} do
    suffix = System.unique_integer([:positive])
    [one, two] = for n <- ["mcp-one-#{suffix}", "mcp-two-#{suffix}"], do: n

    assert {:ok, _} =
             GenAgentServer.start_instance(one, [
               {"alpha", GenAgentEnsemble.Agents.Simple,
                [backend: GenAgentEnsemble.Backends.Echo]}
             ])

    assert {:ok, _} =
             GenAgentServer.start_instance(two, [
               {"beta", GenAgentEnsemble.Agents.Simple, [backend: GenAgentEnsemble.Backends.Echo]}
             ])

    on_exit(fn ->
      GenAgentServer.stop_instance(one)
      GenAgentServer.stop_instance(two)
    end)

    assert %{"instances" => instances} = ok!(client, "instances", %{})
    assert one in instances and two in instances

    assert %{"agents" => ["alpha"]} = ok!(client, "agents", %{"instance" => one})
    assert %{"agents" => ["beta"]} = ok!(client, "agents", %{"instance" => two})

    assert %{"id" => id_one} =
             ok!(client, "invoke", %{"instance" => one, "agent" => "alpha", "prompt" => "one"})

    assert %{"id" => id_two} =
             ok!(client, "invoke", %{"instance" => two, "agent" => "beta", "prompt" => "two"})

    assert eventually(fn ->
             match?(
               %{"status" => "completed"},
               ok!(client, "result", %{"instance" => one, "id" => id_one})
             ) and
               match?(
                 %{"status" => "completed"},
                 ok!(client, "result", %{"instance" => two, "id" => id_two})
               )
           end)

    assert %{"text" => "echo: one"} = ok!(client, "result", %{"instance" => one, "id" => id_one})
    assert %{"text" => "echo: two"} = ok!(client, "result", %{"instance" => two, "id" => id_two})

    assert error!(client, "result", %{"instance" => one, "id" => id_two}) =~ "not_found"

    assert error!(client, "invoke", %{"instance" => one, "agent" => "beta", "prompt" => "x"}) =~
             "unknown_agent"
  end

  describe "telemetry source" do
    setup do
      handler = "mcp-telemetry-#{System.unique_integer([:positive])}"
      test = self()

      :ok =
        :telemetry.attach(
          handler,
          [:gen_agent_server, :invocation, :start],
          fn _event, _measurements, metadata, _ -> send(test, {:start, metadata}) end,
          nil
        )

      on_exit(fn -> :telemetry.detach(handler) end)
    end

    test "MCP invoke and ask are :mcp; existing Ops callers stay :api", %{client: client} do
      assert %{"id" => id} = ok!(client, "invoke", %{"agent" => "echo", "prompt" => "a"})
      assert_receive {:start, %{invocation_id: ^id, source: :mcp}}

      ok!(client, "ask", %{"agent" => "echo", "prompt" => "b"})
      assert_receive {:start, %{source: :mcp}}

      assert {:ok, %{id: api_id}} = Ops.call("invoke", %{"agent" => "echo", "prompt" => "c"})
      assert_receive {:start, %{invocation_id: ^api_id, source: :api}}

      assert {:ok, %{status: "completed"}} =
               Ops.call("ask", %{"agent" => "echo", "prompt" => "d"})

      assert_receive {:start, %{source: :api}}
    end

    test "callers cannot choose the source through arguments" do
      assert {:error, %{code: "invalid_args"}} =
               Ops.call("invoke", %{"agent" => "echo", "prompt" => "x", :source => :mcp})
    end
  end

  describe "stdio transport" do
    @describetag :stdio
    @describetag timeout: 120_000

    test "serves protocol-only stdout from a Mix checkout" do
      mix = System.find_executable("mix") || flunk("mix not found on PATH")

      port =
        Port.open({:spawn_executable, mix}, [
          :binary,
          :exit_status,
          {:line, 1_000_000},
          {:args, ["gen_agent_server.mcp"]},
          {:env, [{~c"MIX_ENV", ~c"test"}, {~c"MIX_QUIET", ~c"1"}]},
          {:cd, File.cwd!()}
        ])

      send_message(port, %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "initialize",
        "params" => %{
          "protocolVersion" => "2025-06-18",
          "capabilities" => %{},
          "clientInfo" => %{"name" => "test", "version" => "0"}
        }
      })

      assert %{
               "result" => %{
                 "serverInfo" => %{"name" => "gen-agent-server"},
                 "instructions" => instructions
               }
             } =
               read_response(port, 1)

      assert instructions =~ "gen-agent://guide/index"

      send_message(port, %{"jsonrpc" => "2.0", "method" => "notifications/initialized"})
      send_message(port, %{"jsonrpc" => "2.0", "id" => 2, "method" => "tools/list"})

      assert %{"result" => %{"tools" => tools}} = read_response(port, 2)
      assert tools |> Enum.map(& &1["name"]) |> Enum.sort() == @tool_names

      send_message(port, %{
        "jsonrpc" => "2.0",
        "id" => 3,
        "method" => "tools/call",
        "params" => %{"name" => "ask", "arguments" => %{"agent" => "echo", "prompt" => "wire"}}
      })

      assert %{"result" => %{"structuredContent" => %{"text" => "echo: wire"}}} =
               read_response(port, 3)

      Port.close(port)
    end
  end

  # -- helpers -----------------------------------------------------------------

  defp send_message(port, message), do: Port.command(port, Jason.encode!(message) <> "\n")

  # Every stdout line must be a JSON-RPC message; anything else fails the test.
  defp read_response(port, id) do
    receive do
      {^port, {:data, {:eol, line}}} ->
        message = Jason.decode!(line)
        assert message["jsonrpc"] == "2.0", "non-protocol stdout: #{line}"
        if message["id"] == id, do: message, else: read_response(port, id)

      {^port, {:exit_status, status}} ->
        flunk("MCP process exited with #{status}")
    after
      60_000 -> flunk("no response to request #{id}")
    end
  end

  defp ok!(client, name, args) do
    {:ok, result} = Snodo.Client.call_tool(client, name, args)
    result = plain(result)
    refute field(result, "isError", :is_error), "#{name} failed: #{inspect(result)}"
    field(result, "structuredContent", :structured_content)
  end

  defp error!(client, name, args) do
    {:ok, result} = Snodo.Client.call_tool(client, name, args)
    result = plain(result)
    assert field(result, "isError", :is_error) == true, "#{name} succeeded: #{inspect(result)}"

    result
    |> field("content", :content)
    |> Enum.map_join(" ", &field(&1, "text", :text))
  end

  # Snodo results may be structs with snake_case keys or wire maps; accept both.
  defp field(map, wire, atom), do: Map.get(map, wire, Map.get(map, atom))

  defp plain(%_{} = struct), do: struct |> Map.from_struct() |> plain()
  defp plain(map) when is_map(map), do: Map.new(map, fn {k, v} -> {k, plain(v)} end)
  defp plain(list) when is_list(list), do: Enum.map(list, &plain/1)
  defp plain(other), do: other

  defp eventually(fun, attempts \\ 100) do
    cond do
      fun.() -> true
      attempts == 0 -> false
      true -> Process.sleep(10) && eventually(fun, attempts - 1)
    end
  end
end

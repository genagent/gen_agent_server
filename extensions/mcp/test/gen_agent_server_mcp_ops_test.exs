defmodule GenAgentServer.MCPOpsTest do
  use ExUnit.Case, async: false

  alias GenAgentServer.{MCP, Ops}

  defmodule Backend do
    @behaviour GenAgent.Backend
    def start_session(opts), do: {:ok, opts[:target]}

    def prompt(target, prompt) do
      send(target, {:entered, prompt, self()})

      receive do
        :finish -> {:ok, [GenAgent.Event.new(:result, %{text: prompt})], target}
      end
    end

    def update_session(session, _), do: session
    def terminate_session(_), do: :ok
  end

  setup do
    {:ok, client} = Snodo.Client.direct(MCP.Server.runtime())
    %{client: client}
  end

  test "cancel over MCP uses the canonical operation", %{client: client} do
    name = "mcp-cancel-#{System.unique_integer([:positive])}"
    agents = [{"worker", GenAgentEnsemble.Agents.Simple, [backend: Backend, target: self()]}]
    assert {:ok, _} = GenAgentServer.start_instance(name, agents, poll_interval_ms: 1)
    on_exit(fn -> GenAgentServer.stop_instance(name) end)

    assert {:ok, id} = GenAgentServer.invoke(name, "worker", "blocked")
    assert_receive {:entered, "blocked", _}
    args = %{"instance" => name, "id" => id}

    assert {:ok,
            %{"structuredContent" => %{"instance" => ^name, "id" => ^id, "status" => "cancelled"}}} =
             Snodo.Client.call_tool(client, "cancel", args)

    assert {:error, %{code: "already_finished"}} = Ops.call("cancel", args)
  end

  test "peer tools report a tool error while peer support is disabled", %{client: client} do
    assert {:ok, %{"isError" => true}} = Snodo.Client.call_tool(client, "discover_peers", %{})
  end

  test "every served tool is an allowlisted catalogue operation with its summary and schema", %{
    client: client
  } do
    assert {:ok, tools} = Snodo.Client.list_tools(client)

    for tool <- tools do
      assert tool["name"] in MCP.allowlist()
      assert {:ok, op} = Ops.fetch(tool["name"])
      assert tool["description"] == op.summary
      assert tool["inputSchema"] == Ops.json_schema(op)
    end

    assert Enum.sort(Enum.map(tools, & &1["name"])) == Enum.sort(MCP.tools())
  end
end

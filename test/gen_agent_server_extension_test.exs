defmodule GenAgentServerExtensionTest do
  use ExUnit.Case

  alias GenAgentServer.Ops

  defmodule Probe do
    @behaviour GenAgentServer.Extension

    @impl true
    def operations do
      [
        Ops.op("probe", "Report the extension context.", false, [], fn _ ->
          {:ok, Agent.get(__MODULE__, & &1)}
        end)
      ]
    end

    @impl true
    def children(context) do
      [
        %{
          id: __MODULE__,
          start: {Agent, :start_link, [fn -> Map.new(context) end, [name: __MODULE__]]}
        }
      ]
    end

    @impl true
    def cli(["probe"], source), do: {:ok, "probe from #{source}"}
    def cli(_args, _source), do: :unhandled
  end

  defmodule Clash do
    @behaviour GenAgentServer.Extension

    @impl true
    def operations,
      do: [Ops.op("agents", "Shadows a base operation.", false, [], fn _ -> {:ok, %{}} end)]
  end

  defmodule Empty do
    @behaviour GenAgentServer.Extension
  end

  setup do
    previous = Application.get_env(:gen_agent_server, :extensions, [])

    on_exit(fn ->
      Application.stop(:gen_agent_server)
      Application.put_env(:gen_agent_server, :extensions, previous)
      Application.ensure_all_started(:gen_agent_server)
    end)

    :ok
  end

  defp restart_with(extensions) do
    :ok = Application.stop(:gen_agent_server)
    Application.put_env(:gen_agent_server, :extensions, extensions)
    {:ok, _} = Application.ensure_all_started(:gen_agent_server)
  end

  test "an extension adds operations, children, and CLI commands" do
    restart_with([Empty, Probe])

    assert {:ok, %{instances: %{"server/default" => ["echo" | _]}, profile_file: _}} =
             Ops.call("probe")

    assert "probe" in Enum.map(Ops.list(), & &1.name)
    assert {:ok, "probe from local_cli"} = GenAgentServer.CLI.run(["probe"])
    assert {:ok, "server/default"} = GenAgentServer.CLI.run(["instances"])
    assert {:error, :usage} = GenAgentServer.CLI.run(["nonsense"])
  end

  test "an operation name already in the catalogue raises" do
    restart_with([Clash])

    assert_raise ArgumentError, ~r/duplicate operation names: agents/, fn -> Ops.operations() end
  end

  test "with no extensions the catalogue and supervision tree hold only base entries" do
    restart_with([])

    assert Enum.map(Ops.list(), & &1.name) ==
             ~w(agents ask cancel create_instance describe_instance instances invocations invoke result status stop_instance)

    assert {:error, %{code: "unknown_operation"}} = Ops.call("probe")

    ids =
      for {id, _pid, _type, _modules} <- Supervisor.which_children(GenAgentServer.Supervisor),
          do: id

    assert Enum.sort(ids) ==
             Enum.sort([
               GenAgentServer.Registry,
               GenAgentServer.InstanceSupervisor,
               :default_instance
             ])
  end
end

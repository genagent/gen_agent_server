defmodule GenAgentServerTest do
  use ExUnit.Case
  import ExUnit.CaptureIO

  defmodule ErrorBackend do
    @behaviour GenAgent.Backend

    def start_session(_opts), do: {:ok, %{}}
    def prompt(session, _prompt), do: {:error, {:fixture_failure, session}}
    def update_session(session, _event), do: session
    def terminate_session(_session), do: :ok
  end

  test "application serves the Echo agent through one local API" do
    assert {:ok, ["echo"]} = GenAgentServer.agents()
    assert {:ok, %{text: "echo: hello"}} = GenAgentServer.ask("echo", "hello")
    assert {:error, {:unknown_agent, "missing"}} = GenAgentServer.ask("missing", "hello")
  end

  test "invocation results survive the caller and can be read repeatedly" do
    parent = self()

    spawn(fn ->
      send(parent, {:invocation, GenAgentServer.invoke("echo", "later")})
    end)

    assert_receive {:invocation, {:ok, id}}
    assert {:ok, :completed, response} = await_result(id)
    assert response.text == "echo: later"
    assert {:ok, :completed, ^response} = GenAgentServer.result(id)
    assert {:ok, :completed, ^response} = GenAgentServer.result(id)
  end

  test "instances isolate results and retain only the configured number" do
    name = "test-instance-#{System.unique_integer([:positive])}"

    agents = [
      {"echo", GenAgentEnsemble.Agents.Simple,
       [backend: GenAgentEnsemble.Backends.Echo, transform: &String.upcase/1]}
    ]

    assert {:ok, _pid} = GenAgentServer.start_instance(name, agents, max_results: 1)
    on_exit(fn -> GenAgentServer.stop_instance(name) end)

    assert {:ok, ["echo"]} = GenAgentServer.agents(name)
    assert {:ok, first} = GenAgentServer.invoke(name, "echo", "first")
    assert {:ok, :completed, %{text: "FIRST"}} = await_result(name, first)
    assert {:error, :not_found} = GenAgentServer.result(first)

    assert {:ok, second} = GenAgentServer.invoke(name, "echo", "second")
    assert {:ok, :completed, %{text: "SECOND"}} = await_result(name, second)
    assert {:error, :not_found} = GenAgentServer.result(name, first)
    assert {:ok, :completed, %{text: "SECOND"}} = GenAgentServer.result(name, second)
    assert :ok = GenAgentServer.stop_instance(name)
    assert {:error, :instance_not_found} = GenAgentServer.result(name, second)
  end

  test "in-flight admission is bounded and unknown agents are rejected" do
    name = "test-bounded-#{System.unique_integer([:positive])}"

    agents = [
      {"slow", GenAgentEnsemble.Agents.Simple,
       [backend: GenAgentEnsemble.Backends.Echo, delay_ms: 200]}
    ]

    assert {:ok, _pid} = GenAgentServer.start_instance(name, agents, max_in_flight: 1)
    on_exit(fn -> GenAgentServer.stop_instance(name) end)

    assert {:error, {:unknown_agent, "missing"}} =
             GenAgentServer.invoke(name, "missing", "hello")

    assert {:ok, id} = GenAgentServer.invoke(name, "slow", "one")
    assert {:error, :busy} = GenAgentServer.invoke(name, "slow", "two")
    assert {:ok, :completed, %{text: "echo: one"}} = await_result(name, id)
    assert {:ok, _id} = GenAgentServer.invoke(name, "slow", "two")
  end

  test "new admission collects a finished turn before applying the in-flight limit" do
    name = "test-admission-#{System.unique_integer([:positive])}"
    agents = [{"echo", GenAgentEnsemble.Agents.Simple, [backend: GenAgentEnsemble.Backends.Echo]}]

    assert {:ok, _pid} =
             GenAgentServer.start_instance(name, agents,
               max_in_flight: 1,
               poll_interval_ms: 1_000
             )

    on_exit(fn -> GenAgentServer.stop_instance(name) end)

    assert {:ok, first} = GenAgentServer.invoke(name, "echo", "one")
    await_ensemble_idle(name)
    assert {:ok, second} = GenAgentServer.invoke(name, "echo", "two")
    assert {:ok, :completed, %{text: "echo: one"}} = GenAgentServer.result(name, first)
    assert {:ok, :completed, %{text: "echo: two"}} = await_result(name, second)
  end

  test "failed turns are retained for repeatable reads" do
    name = "test-failure-#{System.unique_integer([:positive])}"

    agents = [{"broken", GenAgentEnsemble.Agents.Simple, [backend: ErrorBackend]}]

    assert {:ok, _pid} = GenAgentServer.start_instance(name, agents)
    on_exit(fn -> GenAgentServer.stop_instance(name) end)

    assert {:ok, id} = GenAgentServer.invoke(name, "broken", "hello")
    assert {:ok, :failed, reason} = await_result(name, id)
    assert reason == {:fixture_failure, %{}}
    assert {:ok, :failed, ^reason} = GenAgentServer.result(name, id)
  end

  test "CLI lists agents and routes an ask" do
    assert capture_io(fn -> assert :ok = GenAgentServer.CLI.main(["agents"]) end) == "echo\n"

    assert capture_io(fn -> assert :ok = GenAgentServer.CLI.main(["ask", "echo", "hello"]) end) ==
             "echo: hello\n"

    assert {:ok, id} = GenAgentServer.CLI.run(["invoke", "echo", "from CLI"])
    assert {:ok, :completed, %{text: "echo: from CLI"}} = await_result(id)
    assert {:ok, "echo: from CLI"} = GenAgentServer.CLI.run(["result", id])
  end

  test "one-shot Mix task rejects result commands that need a persistent release" do
    assert_raise Mix.Error, ~r/require a running server/, fn ->
      Mix.Tasks.GenAgentServer.run(["invoke", "echo", "hello"])
    end

    assert_raise Mix.Error, ~r/require a running server/, fn ->
      Mix.Tasks.GenAgentServer.run(["result", "inv-1"])
    end
  end

  test "remote command encodes quoted prompts as data" do
    prompt = ~S|What's "next"; #{GenAgentServer.stop()}|
    expression = GenAgentServer.Remote.expression(["ask", "echo", prompt])

    assert capture_io(fn -> Code.eval_string(expression) end) == "echo: #{prompt}\n"
  end

  test "remote command reports an inaccessible release executable" do
    previous = System.get_env("GEN_AGENT_SERVER_RELEASE_BIN")
    System.put_env("GEN_AGENT_SERVER_RELEASE_BIN", Path.expand("README.md"))

    try do
      assert_raise Mix.Error, ~r/server RPC could not start/, fn ->
        Mix.Tasks.GenAgentServer.Remote.run(["agents"])
      end
    after
      if previous do
        System.put_env("GEN_AGENT_SERVER_RELEASE_BIN", previous)
      else
        System.delete_env("GEN_AGENT_SERVER_RELEASE_BIN")
      end
    end
  end

  defp await_result(id), do: await_result(GenAgentServer.session_name(), id)

  defp await_ensemble_idle(name) do
    deadline = System.monotonic_time(:millisecond) + 2_000
    wait_ensemble_idle(name, deadline)
  end

  defp wait_ensemble_idle(name, deadline) do
    case GenAgentEnsemble.status(name) do
      {:ok, %{in_flight: 0}} ->
        :ok

      _ ->
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(10)
          wait_ensemble_idle(name, deadline)
        else
          flunk("timed out waiting for ensemble #{name}")
        end
    end
  end

  defp await_result(instance, id) do
    deadline = System.monotonic_time(:millisecond) + 2_000
    poll_result(instance, id, deadline)
  end

  defp poll_result(instance, id, deadline) do
    case GenAgentServer.result(instance, id) do
      {:ok, :pending} ->
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(10)
          poll_result(instance, id, deadline)
        else
          flunk("timed out waiting for invocation #{id}")
        end

      outcome ->
        outcome
    end
  end
end

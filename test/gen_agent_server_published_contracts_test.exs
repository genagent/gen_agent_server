defmodule GenAgentServerPublishedContractsTest do
  use ExUnit.Case, async: false

  defmodule GatedBackend do
    @behaviour GenAgent.Backend
    def start_session(opts), do: {:ok, opts[:target]}

    def prompt(target, prompt) do
      send(target, {:entered, prompt, self()})

      receive do
        :finish -> {:ok, [GenAgent.Event.new(:result, %{text: prompt})], target}
      end
    end

    def terminate_session(_), do: :ok
  end

  defp name, do: "published-#{System.unique_integer([:positive])}"

  defp eventually(fun, tries \\ 200)
  defp eventually(fun, 0), do: flunk("condition did not hold: #{inspect(fun.())}")

  defp eventually(fun, tries) do
    if fun.() do
      :ok
    else
      Process.sleep(5)
      eventually(fun, tries - 1)
    end
  end

  test "every admitted completion survives a burst before inbox collection" do
    name = name()

    agents =
      for i <- 1..101,
          do: {"w#{i}", GenAgentEnsemble.Agents.Simple, [backend: GatedBackend, target: self()]}

    assert {:ok, _} =
             GenAgentServer.start_instance(name, agents,
               max_in_flight: 101,
               max_results: 101,
               poll_interval_ms: 60_000
             )

    on_exit(fn -> GenAgentServer.stop_instance(name) end)

    ids =
      for i <- 1..101 do
        assert {:ok, id} = GenAgentServer.invoke(name, "w#{i}", "p#{i}")
        id
      end

    workers =
      for _ <- 1..101 do
        assert_receive {:entered, _, pid}, 1_000
        pid
      end

    Enum.each(workers, &send(&1, :finish))

    eventually(fn ->
      {:ok, status} = GenAgentEnsemble.status(name)
      status.pending_tokens == []
    end)

    results = Enum.map(ids, &GenAgentServer.result(name, &1))
    assert Enum.count(results, &match?({:ok, :completed, _}, &1)) == 101
    assert Enum.map(ids, &GenAgentServer.result(name, &1)) == results
    assert {:ok, summaries} = GenAgentServer.invocations(name, limit: 200)
    assert length(summaries) == 101
    assert Enum.all?(summaries, &(&1.status == :completed))
  end

  test "invalid direct admission limits remain rejected without an instance" do
    for limit <- [0, -1, "101"] do
      name = name()

      agents = [
        {"worker", GenAgentEnsemble.Agents.Simple, [backend: GatedBackend, target: self()]}
      ]

      assert {:error, _} = GenAgentServer.start_instance(name, agents, max_in_flight: limit)
      assert Registry.lookup(GenAgentServer.Registry, {:instance, name}) == []
    end
  end

  test "published member names are JSON-safe and halt retains terminal results" do
    name = name()
    agent = {"worker", GenAgentEnsemble.Agents.Simple, [backend: GatedBackend, target: self()]}

    assert {:ok, _} =
             GenAgentServer.start_instance(name, [agent],
               strategy: GenAgentEnsemble.Strategies.Solo,
               strategy_opts: [agent: agent],
               poll_interval_ms: 60_000
             )

    on_exit(fn -> GenAgentServer.stop_instance(name) end)
    assert {:ok, status} = GenAgentServer.Ops.call("status", %{"instance" => name})
    assert status["member_names"] == %{"worker" => ["GenAgentEnsemble", name, "worker"]}
    assert {:ok, _} = Jason.encode(status)

    assert {:ok, id} = GenAgentServer.invoke(name, "worker", "halt")
    assert_receive {:entered, "halt", task}, 1_000
    on_exit(fn -> send(task, :finish) end)
    pid = GenAgent.whereis(GenAgentEnsemble.member_name(name, "worker"))
    assert is_pid(pid)
    Process.exit(pid, :kill)

    eventually(fn ->
      {:ok, status} = GenAgentServer.status(name)
      status.lifecycle == :halted
    end)

    assert {:ok, :failed, {:halted, _}} = result = GenAgentServer.result(name, id)
    assert GenAgentServer.result(name, id) == result
    assert {:error, {:halted, _}} = GenAgentServer.invoke(name, "worker", "rejected")
    assert :ok = GenAgentServer.stop_instance(name)
    assert {:ok, _} = GenAgentServer.start_instance(name, [agent])
  end
end

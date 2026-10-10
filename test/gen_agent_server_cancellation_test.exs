defmodule GenAgentServerCancellationTest do
  use ExUnit.Case, async: false

  defmodule EnsembleFixture do
    use GenServer

    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts,
        name: {:via, Registry, {GenAgentEnsemble.Registry, opts[:name]}}
      )
    end

    def init(opts), do: {:ok, %{target: opts[:target], entries: [], mode: :cancelled, n: 0}}

    def handle_call(:status, _, state),
      do: {:reply, {:ok, %{agents: [], strategy: __MODULE__}}, state}

    def handle_call({:tell, prompt, opts}, _, state) do
      token = "token-#{state.n}"
      send(state.target, {:tell, token, prompt, opts})
      {:reply, {:ok, token}, %{state | n: state.n + 1}}
    end

    def handle_call(:inbox, _, state),
      do: {:reply, {:ok, state.entries}, %{state | entries: []}}

    def handle_call({:entries, entries}, _, state),
      do: {:reply, :ok, %{state | entries: entries}}

    def handle_call({:mode, mode}, _, state), do: {:reply, :ok, %{state | mode: mode}}

    def handle_call({:cancel, token}, from, state) do
      send(state.target, {:cancel_called, token})

      case state.mode do
        {:finished, outcome} ->
          {:reply, {:error, :already_finished}, %{state | entries: [{token, outcome}]}}

        :hold ->
          send(state.target, {:cancel_held, from, token})
          {:noreply, state}

        :unsupported ->
          {:reply, {:error, :unsupported}, state}

        ack ->
          {:reply, {:ok, ack}, %{state | entries: [{token, {:error, :cancelled}}]}}
      end
    end

    def handle_call({:release, from, token}, _, state) do
      GenServer.reply(from, {:ok, :cancelled})
      {:reply, :ok, %{state | entries: [{token, {:error, :cancelled}}]}}
    end
  end

  defmodule ControlledBackend do
    @behaviour GenAgent.Backend
    def start_session(opts), do: {:ok, opts[:target]}

    def prompt(target, prompt) do
      send(target, {:entered, prompt, self()})

      receive do
        :release -> {:ok, [GenAgent.Event.new(:result, %{text: prompt})], target}
      end
    end

    def update_session(session, _), do: session
    def terminate_session(_), do: :ok
  end

  defmodule UnsupportedStrategy do
    @behaviour GenAgentEnsemble.Strategy
    def init(opts), do: {:ok, opts[:target], []}

    def handle_tell(_, _, token, target) do
      send(target, {:strategy_token, token})
      {:ok, [], target}
    end

    def handle_ask(prompt, opts, token, state), do: handle_tell(prompt, opts, token, state)
    def handle_response(_, _, state), do: {:ok, [], state}

    def handle_notify({:finish, token}, state),
      do: {:ok, [{:reply, token, %{text: "done"}}], state}
  end

  defp name, do: "cancel-test-#{System.unique_integer([:positive])}"

  defp fixture(opts \\ []) do
    name = name()
    ensemble = start_supervised!({EnsembleFixture, name: name, target: self()}, id: name)

    owner =
      start_supervised!(
        {GenAgentServer.Invocations,
         name: name,
         agents: [],
         routes: ["worker"],
         strategy: EnsembleFixture,
         max_in_flight: Keyword.get(opts, :max_in_flight, 4),
         max_results: Keyword.get(opts, :max_results, 10),
         poll_interval_ms: 60_000},
        id: {name, :owner}
      )

    {name, ensemble, owner}
  end

  defp invoke(name, opts \\ []) do
    assert {:ok, id} = GenAgentServer.invoke(name, "worker", "secret", opts)
    assert_receive {:tell, token, "secret", forwarded}
    {id, token, forwarded}
  end

  test "both acknowledgements finalize once, retain reads, fence late events, and classify telemetry" do
    handler = "cancel-telemetry-#{name()}"

    :ok =
      :telemetry.attach(
        handler,
        [:gen_agent_server, :invocation, :error],
        &__MODULE__.telemetry/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    for ack <- [:cancelled, :cancelled_unconfirmed] do
      {name, ensemble, owner} = fixture()
      :ok = GenServer.call(ensemble, {:mode, ack})
      {id, token, _} = invoke(name, recipient: self(), source: :mcp)
      assert {:ok, ^ack} = GenAgentServer.cancel(name, id)
      assert_receive {:cancel_called, ^token}
      assert_receive {:gen_agent_server, :completion, metadata, {:ok, :failed, :cancelled}}

      assert metadata == %{
               instance: name,
               agent: "worker",
               invocation_id: id,
               ensemble_token: token,
               source: :mcp,
               cancellation_ack: ack
             }

      assert_receive {:terminal_error, %{duration_ms: duration}, telemetry}
      assert duration >= 0
      assert telemetry == Map.put(metadata, :error_kind, :cancelled)
      assert {:error, :already_finished} = GenAgentServer.cancel(name, id)
      for _ <- 1..2, do: assert({:ok, :failed, :cancelled} = GenAgentServer.result(name, id))
      {other, other_token, _} = invoke(name)

      :ok =
        GenServer.call(
          ensemble,
          {:entries,
           [{token, {:ok, :late}}, {token, {:error, :duplicate}}, {other_token, {:ok, :done}}]}
        )

      assert {:ok, :completed, :done} = GenAgentServer.result(name, other)
      assert {:ok, :failed, :cancelled} = GenAgentServer.result(name, id)
      assert Process.alive?(owner)
      refute_receive {:gen_agent_server, :completion, _, _}, 0
      refute_receive {:terminal_error, _, _}, 0
      refute_receive {:cancel_called, _}, 0
    end
  end

  def telemetry(_, measurements, metadata, target),
    do: send(target, {:terminal_error, measurements, metadata})

  test "success and failure notify before batch eviction; reads do not refresh order" do
    {name, ensemble, _} = fixture(max_results: 1)
    {a, ta, _} = invoke(name, recipient: self())
    {b, tb, _} = invoke(name, recipient: self())
    :ok = GenServer.call(ensemble, {:entries, [{ta, {:ok, :success}}, {tb, {:error, :failure}}]})
    assert {:ok, :failed, :failure} = GenAgentServer.result(name, b)

    assert_receive {:gen_agent_server, :completion, %{invocation_id: ^a},
                    {:ok, :completed, :success}}

    assert_receive {:gen_agent_server, :completion, %{invocation_id: ^b},
                    {:ok, :failed, :failure}}

    assert {:error, :not_found} = GenAgentServer.cancel(name, a)
    assert {:error, :already_finished} = GenAgentServer.cancel(name, b)
    assert {:ok, :failed, :failure} = GenAgentServer.result(name, b)
    {c, tc, _} = invoke(name)
    :ok = GenServer.call(ensemble, {:entries, [{tc, {:ok, :next}}]})
    assert {:ok, :completed, :next} = GenAgentServer.result(name, c)
    assert {:error, :not_found} = GenAgentServer.result(name, b)
  end

  test "completion wins both drain boundaries and external cancellation is unconfirmed" do
    {name, ensemble, _} = fixture()
    {id, token, _} = invoke(name, recipient: self())
    :ok = GenServer.call(ensemble, {:entries, [{token, {:ok, :first}}]})
    assert {:error, :already_finished} = GenAgentServer.cancel(name, id)
    refute_receive {:cancel_called, _}, 0
    assert {:ok, :completed, :first} = GenAgentServer.result(name, id)

    assert_receive {:gen_agent_server, :completion, %{invocation_id: ^id},
                    {:ok, :completed, :first}}

    for outcome <- [{:ok, :race}, {:error, :race_failure}] do
      {id, token, _} = invoke(name, recipient: self())
      :ok = GenServer.call(ensemble, {:mode, {:finished, outcome}})
      assert {:error, :already_finished} = GenAgentServer.cancel(name, id)
      assert_receive {:cancel_called, ^token}

      expected =
        case outcome do
          {:ok, value} -> {:ok, :completed, value}
          {:error, reason} -> {:ok, :failed, reason}
        end

      assert ^expected = GenAgentServer.result(name, id)
      assert_receive {:gen_agent_server, :completion, %{invocation_id: ^id}, ^expected}
    end

    {id, token, _} = invoke(name, recipient: self())
    :ok = GenServer.call(ensemble, {:entries, [{token, {:error, :cancelled}}]})
    assert {:ok, :failed, :cancelled} = GenAgentServer.result(name, id)

    assert_receive {:gen_agent_server, :completion,
                    %{invocation_id: ^id, cancellation_ack: :cancelled_unconfirmed},
                    {:ok, :failed, :cancelled}}
  end

  test "recipient validation precedes admission and all option keys are stripped" do
    {name, ensemble, owner} = fixture(max_in_flight: 1)

    for invalid <- [:bad, "pid", 1] do
      assert {:error, :invalid_recipient} =
               GenAgentServer.invoke(name, "worker", "secret", recipient: invalid)
    end

    refute_receive {:tell, _, _, _}, 0
    {id, token, opts} = invoke(name, recipient: self(), recipient: nil, source: :api, custom: 1)
    assert opts == [custom: 1]

    assert {:error, :invalid_recipient} =
             GenAgentServer.invoke(name, "worker", "secret", recipient: :bad)

    :ok = GenServer.call(ensemble, {:entries, [{token, {:ok, :done}}]})
    assert {:ok, :completed, :done} = GenAgentServer.result(name, id)
    assert_receive {:gen_agent_server, :completion, _, _}
    {dead, monitor} = spawn_monitor(fn -> :ok end)
    assert_receive {:DOWN, ^monitor, :process, ^dead, :normal}
    {id, token, _} = invoke(name, recipient: dead)
    :ok = GenServer.call(ensemble, {:entries, [{token, {:error, :dead}}]})
    assert {:ok, :failed, :dead} = GenAgentServer.result(name, id)
    assert Process.alive?(owner)
    parent = self()

    {_, monitor} =
      spawn_monitor(fn ->
        send(
          parent,
          {:submitted, GenAgentServer.invoke(name, "worker", "secret", recipient: parent)}
        )
      end)

    assert_receive {:submitted, {:ok, id}}
    assert_receive {:tell, token, _, _}
    assert_receive {:DOWN, ^monitor, :process, _, :normal}
    :ok = GenServer.call(ensemble, {:entries, [{token, {:ok, :survived}}]})
    assert {:ok, :completed, :survived} = GenAgentServer.result(name, id)

    assert_receive {:gen_agent_server, :completion, %{invocation_id: ^id},
                    {:ok, :completed, :survived}}
  end

  test "held cancellation blocks owner until released" do
    {name, ensemble, _} = fixture()
    {id, token, _} = invoke(name)
    :ok = GenServer.call(ensemble, {:mode, :hold})
    task = Task.async(fn -> GenAgentServer.cancel(name, id) end)
    assert_receive {:cancel_called, ^token}
    assert_receive {:cancel_held, from, ^token}
    assert Task.yield(task, 0) == nil
    :ok = GenServer.call(ensemble, {:release, from, token})
    assert {:ok, :cancelled} = Task.await(task)
    assert {:ok, :failed, :cancelled} = GenAgentServer.result(name, id)
  end

  test "recipient_ref is validated, stripped and echoed only when supplied" do
    {name, ensemble, _} = fixture()

    assert {:error, :invalid_recipient_ref} =
             GenAgentServer.invoke(name, "worker", "secret", recipient_ref: "invalid")

    refute_receive {:tell, _, _, _}, 0
    ref = make_ref()
    {id, token, opts} = invoke(name, recipient: self(), recipient_ref: ref)
    assert opts == []
    :ok = GenServer.call(ensemble, {:entries, [{token, {:ok, :done}}]})
    assert {:ok, :completed, :done} = GenAgentServer.result(name, id)
    assert_receive {:gen_agent_server, :completion, %{recipient_ref: ^ref, invocation_id: ^id}, _}
  end

  test "nil recipient retains a result without sending a notification" do
    {name, ensemble, _} = fixture()
    {id, token, opts} = invoke(name, recipient: nil)
    assert opts == []
    :ok = GenServer.call(ensemble, {:entries, [{token, {:ok, :quiet}}]})
    assert {:ok, :completed, :quiet} = GenAgentServer.result(name, id)
    assert {:ok, :completed, :quiet} = GenAgentServer.result(name, id)
    assert {:error, :already_finished} = GenAgentServer.cancel(name, id)
    refute_receive {:gen_agent_server, :completion, _, _}, 0
  end

  test "unknown, wrong instance and previous generation IDs are isolated" do
    {name, _, _} = fixture()
    {other, _, _} = fixture()
    {id, _, _} = invoke(name)
    assert {:error, :not_found} = GenAgentServer.cancel(other, id)
    assert {:error, :not_found} = GenAgentServer.cancel(name, "unknown")
    :ok = stop_supervised({name, :owner})
    assert {:error, :instance_not_found} = GenAgentServer.cancel(name, id)

    start_supervised!(
      {GenAgentServer.Invocations,
       name: name,
       agents: [],
       routes: ["worker"],
       strategy: EnsembleFixture,
       max_in_flight: 1,
       max_results: 1,
       poll_interval_ms: 60_000},
      id: {name, :owner}
    )

    assert {:error, :not_found} = GenAgentServer.cancel(name, id)
  end

  test "real Ensemble unsupported custom strategy remains pending and later notifies" do
    name = name()

    assert {:ok, _} =
             GenAgentServer.start_pattern_instance(
               name,
               "worker",
               UnsupportedStrategy,
               [target: self()],
               poll_interval_ms: 60_000
             )

    on_exit(fn -> GenAgentServer.stop_instance(name) end)
    assert {:ok, id} = GenAgentServer.invoke(name, "worker", "secret", recipient: self())
    assert_receive {:strategy_token, token}
    assert {:error, :unsupported} = GenAgentServer.cancel(name, id)
    assert {:ok, :pending} = GenAgentServer.result(name, id)
    GenAgentEnsemble.notify(name, {:finish, token})
    assert {:ok, :completed, %{text: "done"}} = GenAgentServer.result(name, id)
    assert_receive {:gen_agent_server, :completion, %{invocation_id: ^id}, {:ok, :completed, _}}
    refute_receive {:gen_agent_server, :completion, _, _}, 0
  end

  test "real switchboard cancellation releases admission while unrelated work continues" do
    name = name()

    agents =
      for worker <- ["a", "b"],
          do:
            {worker, GenAgentEnsemble.Agents.Simple, [backend: ControlledBackend, target: self()]}

    assert {:ok, _} =
             GenAgentServer.start_instance(name, agents, max_in_flight: 2, poll_interval_ms: 1)

    on_exit(fn -> GenAgentServer.stop_instance(name) end)
    assert {:ok, a} = GenAgentServer.invoke(name, "a", "cancel", recipient: self())
    assert_receive {:entered, "cancel", _}
    assert {:ok, b} = GenAgentServer.invoke(name, "b", "unrelated", recipient: self())
    assert_receive {:entered, "unrelated", worker}
    assert {:error, :busy} = GenAgentServer.invoke(name, "a", "busy")
    assert {:ok, :cancelled} = GenAgentServer.cancel(name, a)
    assert {:ok, :failed, :cancelled} = GenAgentServer.result(name, a)

    assert_receive {:gen_agent_server, :completion,
                    %{invocation_id: ^a, cancellation_ack: :cancelled}, _}

    assert {:ok, c} = GenAgentServer.invoke(name, "a", "replacement", recipient: self())
    assert_receive {:entered, "replacement", replacement}
    send(worker, :release)
    send(replacement, :release)

    assert_receive {:gen_agent_server, :completion, %{invocation_id: ^b},
                    {:ok, :completed, %{text: "unrelated"}}},
                   2_000

    assert_receive {:gen_agent_server, :completion, %{invocation_id: ^c}, {:ok, :completed, _}},
                   2_000

    assert {:ok, :failed, :cancelled} = GenAgentServer.result(name, a)
  end

  test "real queued pipeline successor proceeds after cancellation" do
    name = name()

    stage =
      {"stage", GenAgentEnsemble.Agents.Simple, [backend: ControlledBackend, target: self()]}

    assert {:ok, _} =
             GenAgentServer.start_pattern_instance(
               name,
               "worker",
               GenAgentEnsemble.Strategies.Pipeline,
               [stages: [stage]],
               poll_interval_ms: 1
             )

    on_exit(fn -> GenAgentServer.stop_instance(name) end)
    assert {:ok, a} = GenAgentServer.invoke(name, "worker", "first")
    assert_receive {:entered, "first", _}
    assert {:ok, b} = GenAgentServer.invoke(name, "worker", "successor", recipient: self())
    assert {:ok, :cancelled} = GenAgentServer.cancel(name, a)
    assert_receive {:entered, "successor", worker}
    send(worker, :release)

    assert_receive {:gen_agent_server, :completion, %{invocation_id: ^b},
                    {:ok, :completed, %{text: "successor"}}},
                   2_000
  end
end

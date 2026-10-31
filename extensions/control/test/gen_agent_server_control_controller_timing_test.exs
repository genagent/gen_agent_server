defmodule GenAgentServer.Control.ControllerTimingTest do
  use ExUnit.Case, async: false
  alias GenAgentServer.Control.{Controller, Ledger}

  # Hold the Ensemble boundary while using real Invocations correlation and
  # completion delivery. Every transition is released by a message or call.
  defmodule GatedEnsemble do
    use GenServer

    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts,
        name: {:via, Registry, {GenAgentEnsemble.Registry, opts[:name]}}
      )
    end

    def init(opts), do: {:ok, %{target: opts[:target], entries: [], n: 0}}
    def handle_call(:status, _, s), do: {:reply, {:ok, %{agents: [], strategy: __MODULE__}}, s}

    def handle_call({:tell, prompt, opts}, from, s) do
      token = "timing-#{s.n}"
      send(s.target, {:tell, from, token, prompt, opts})
      {:noreply, %{s | n: s.n + 1}}
    end

    def handle_call({:entries, entries}, _, s), do: {:reply, :ok, %{s | entries: entries}}
    def handle_call(:inbox, _, s), do: {:reply, {:ok, s.entries}, %{s | entries: []}}

    def handle_call({:cancel, token}, from, s) do
      send(s.target, {:cancel_called, from, token})
      {:noreply, s}
    end
  end

  defp spec(changes \\ %{}) do
    Map.merge(
      %{
        stage: "work",
        kind: :work,
        provider: "echo",
        requested_settings: %{},
        instruction_revision: "v1",
        checkout: File.cwd!(),
        prompt: "work"
      },
      changes
    )
  end

  defp fixture(controller_limits \\ [], ledger_limits \\ []) do
    name = "timing-#{System.unique_integer([:positive])}"
    ensemble = start_supervised!({GatedEnsemble, name: name, target: self()})

    owner =
      start_supervised!(
        {GenAgentServer.Invocations,
         name: name,
         agents: [],
         routes: ["worker"],
         strategy: GatedEnsemble,
         max_in_flight: 8,
         max_results: 1,
         poll_interval_ms: 5_000,
         description: %{
           configured: true,
           routes: [%{name: "worker", provider: "echo", cwd: File.cwd!()}]
         }}
      )

    ledger = start_supervised!({Ledger, limits: ledger_limits})

    {:ok, run} =
      Ledger.open(ledger, %{
        name: "timing",
        control_revision: "v1",
        tasks: [%{name: "task", checkout: File.cwd!(), required_checks: []}]
      })

    controller =
      start_supervised!(
        {Controller, instance: name, ledger: ledger, run: run, limits: controller_limits}
      )

    %{name: name, ensemble: ensemble, owner: owner, ledger: ledger, run: run, c: controller}
  end

  defp attempt(f, id) do
    {:ok, snapshot} = Controller.status(f.c)
    snapshot.attempts[id]
  end

  defp held_submit(f, spec \\ spec()) do
    before_wall = System.system_time(:millisecond)
    before_mono = System.monotonic_time(:millisecond)
    assert {:ok, id} = Controller.submit(f.c, "task", "worker", spec)
    after_wall = System.system_time(:millisecond)
    after_mono = System.monotonic_time(:millisecond)
    assert_receive {:tell, from, token, _, []}
    a = attempt(f, id)
    assert a.timing.admitted_at_unix_ms in before_wall..after_wall
    assert a.timing.terminal_observed_after_ms == nil
    refute Map.has_key?(a, :admitted_monotonic_ms)
    private = :sys.get_state(f.c).attempts[id]
    assert private.admitted_monotonic_ms in before_mono..after_mono
    {id, from, token}
  end

  # The helper sends its reply before exiting. Waiting for that exit then reading
  # the controller gives a barrier without a sleep or a polling deadline.
  defp release_helper(f, from, reply) do
    [h] = Map.values(:sys.get_state(f.c).helpers)
    ref = Process.monitor(h.pid)
    GenServer.reply(from, reply)
    assert_receive {:DOWN, ^ref, :process, _, :normal}, 1_000
    Controller.status(f.c)
  end

  defp complete(f, token, outcome) do
    :ok = GenServer.call(f.ensemble, {:entries, [{token, outcome}]})
    send(f.owner, :collect)
    # The owner sends completion before answering this barrier call.
    {:ok, _} = GenServer.call(f.owner, :describe)
    Controller.status(f.c)
  end

  defp observed(f, id, status) do
    a = attempt(f, id)
    assert a.execution == status
    assert is_integer(a.timing.terminal_observed_after_ms)
    assert a.timing.terminal_observed_after_ms >= 0
    a
  end

  test "work and review timing uses milliseconds and survives duplicate reads, submits and events" do
    f = fixture()
    {work, from, token} = held_submit(f)
    admitted = attempt(f, work).timing
    assert Controller.submit(f.c, "task", "worker", spec()) == {:ok, work}
    assert attempt(f, work).timing == admitted
    release_helper(f, from, {:ok, token})

    # Advance only the private start to check elapsed units without a fixed sleep.
    :sys.replace_state(f.c, fn s ->
      update_in(s, [:attempts, work, :admitted_monotonic_ms], &(&1 - 1_234))
    end)

    start = :sys.get_state(f.c).attempts[work].admitted_monotonic_ms
    before_observation = System.monotonic_time(:millisecond)
    complete(f, token, {:ok, %{text: "done"}})
    after_observation = System.monotonic_time(:millisecond)
    work_result = observed(f, work, :completed)
    assert work_result.timing.terminal_observed_after_ms >= 1_234

    assert work_result.timing.terminal_observed_after_ms in (before_observation - start)..(after_observation -
                                                                                             start)

    assert work_result.timing.admitted_at_unix_ms == admitted.admitted_at_unix_ms

    {:ok, revision} =
      Ledger.record_revision(f.ledger, f.run, %{
        task: "task",
        produced_by_attempt_id: work,
        content_sha256: String.duplicate("a", 64),
        recorded_by: "caller"
      })

    review = spec(%{stage: "review", kind: :review, subject_revision_id: revision})
    {id, from, token} = held_submit(f, review)
    release_helper(f, from, {:ok, token})
    complete(f, token, {:ok, %{text: "APPROVE"}})
    a = observed(f, id, :completed)
    assert Controller.submit(f.c, "task", "worker", review) == {:ok, id}
    private = :sys.get_state(f.c).attempts[id]
    metadata = %{instance: f.name, recipient_ref: private.ref, invocation_id: a.invocation_id}
    send(f.c, {:gen_agent_server, :completion, metadata, {:ok, :failed, :cancelled}})
    assert attempt(f, id) == a
    {:ok, snapshot} = Controller.status(f.c)
    assert Controller.result(f.c) == {:ok, snapshot}
    assert Controller.status(f.c) == {:ok, snapshot}
    {:ok, stored} = Ledger.result(f.ledger, f.run)
    refute Map.has_key?(stored.attempts[id], :timing)
    refute Map.has_key?(stored.attempts[id].terminal, :timing)
    refute Enum.any?(stored.records, &(&1.kind in [:review, :acceptance]))
  end

  test "definite admission rejection records a first observation and ignores late completion" do
    f = fixture()
    {id, from, _} = held_submit(f)
    release_helper(f, from, {:error, :definite_rejection})
    a = observed(f, id, :admission_failed)
    assert a.terminal.status == :admission_failed
    private = :sys.get_state(f.c).attempts[id]
    metadata = %{instance: f.name, recipient_ref: private.ref, invocation_id: "late"}
    send(f.c, {:gen_agent_server, :completion, metadata, {:ok, :completed, %{text: "late"}}})
    assert attempt(f, id) == a
  end

  for {reason, status} <- [{:failure, :failed}, {:cancelled, :cancelled}] do
    test "authoritative #{status} result records elapsed timing" do
      f = fixture()
      {id, from, token} = held_submit(f)
      release_helper(f, from, {:ok, token})
      complete(f, token, {:error, unquote(reason)})
      assert observed(f, id, unquote(status)).terminal.status == unquote(status)
    end
  end

  test "cancel acknowledgement alone has no terminal observation" do
    f = fixture()
    {id, from, token} = held_submit(f)
    release_helper(f, from, {:ok, token})
    assert Controller.cancel(f.c, id) == {:ok, :requested}
    assert_receive {:cancel_called, from, ^token}
    assert attempt(f, id).timing.terminal_observed_after_ms == nil
    release_helper(f, from, {:ok, :cancelled_unconfirmed})
    assert attempt(f, id).cancel == {:ok, :cancelled_unconfirmed}
    assert attempt(f, id).timing.terminal_observed_after_ms == nil
    complete(f, token, {:error, :cancelled})
    a = observed(f, id, :cancelled)
    assert Controller.cancel(f.c, id) == {:ok, {:ok, :cancelled_unconfirmed}}
    assert attempt(f, id) == a
  end

  test "uncertain admission has no duration until same-owner authoritative completion" do
    f = fixture()
    {id, from, token} = held_submit(f)
    [tag] = Map.keys(:sys.get_state(f.c).helpers)
    send(f.c, {:helper_timeout, tag})
    a = attempt(f, id)
    assert a.execution == :unobserved
    assert a.timing.terminal_observed_after_ms == nil
    assert Controller.submit(f.c, "task", "worker", spec()) == {:ok, id}
    GenServer.reply(from, {:ok, token})
    complete(f, token, {:ok, %{text: "late"}})
    assert observed(f, id, :completed).timing.admitted_at_unix_ms == a.timing.admitted_at_unix_ms
  end

  test "owner fencing leaves timing nil even on a correlated late notification" do
    f = fixture()
    {id, from, token} = held_submit(f)
    release_helper(f, from, {:ok, token})
    private = :sys.get_state(f.c).attempts[id]
    :ok = stop_supervised(GenAgentServer.Invocations)
    a = attempt(f, id)
    assert a.execution == :unobserved
    assert a.timing.terminal_observed_after_ms == nil
    metadata = %{instance: f.name, recipient_ref: private.ref, invocation_id: a.invocation_id}
    send(f.c, {:gen_agent_server, :completion, metadata, {:ok, :completed, %{text: "late"}}})
    assert attempt(f, id) == a
  end

  test "an unknown completion result never fabricates terminal timing" do
    f = fixture()
    {id, from, token} = held_submit(f)
    release_helper(f, from, {:ok, token})
    private = :sys.get_state(f.c).attempts[id]

    metadata = %{
      instance: f.name,
      recipient_ref: private.ref,
      invocation_id: private.invocation_id
    }

    send(f.c, {:gen_agent_server, :completion, metadata, :unknown})
    a = attempt(f, id)
    assert a.evidence_error == :invalid_completion
    assert a.terminal == nil
    assert a.timing.terminal_observed_after_ms == nil
  end

  for {limits, ledger_limits, text, error} <- [
        {[text_bytes: 4], [], "oversized", :output_not_retainable},
        {[], [record_bytes: 1024], String.duplicate("x", 1000), :quota_exhausted}
      ] do
    test "completed observation survives #{error} evidence failure" do
      f = fixture(unquote(limits), unquote(ledger_limits))
      {id, from, token} = held_submit(f)
      release_helper(f, from, {:ok, token})
      complete(f, token, {:ok, %{text: unquote(text)}})
      a = observed(f, id, :completed)
      assert a.evidence_error == unquote(error)
      assert a.terminal == nil
      {:ok, stored} = Ledger.result(f.ledger, f.run)
      assert stored.attempts[id].terminal == nil
      assert stored.attempts[id].reserved_bytes > 0
      assert Controller.submit(f.c, "task", "worker", spec()) == {:ok, id}
      assert attempt(f, id) == a
    end
  end

  test "ledger loss leaves observation nil until completed execution, retaining duration without evidence" do
    f = fixture()
    {id, from, token} = held_submit(f)
    release_helper(f, from, {:ok, token})
    :ok = stop_supervised(Ledger)
    assert attempt(f, id).timing.terminal_observed_after_ms == nil
    complete(f, token, {:ok, %{text: "done"}})
    a = observed(f, id, :completed)
    assert a.terminal == nil
    assert a.evidence_error == :ledger_unavailable
    :ok = stop_supervised(GenAgentServer.Invocations)
    assert attempt(f, id) == a
  end
end

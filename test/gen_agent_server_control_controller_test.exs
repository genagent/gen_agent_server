defmodule GenAgentServer.Control.ControllerTest do
  use ExUnit.Case, async: false
  alias GenAgentServer.Control.{Controller, Ledger}

  defmodule GatedBackend do
    @behaviour GenAgent.Backend
    def start_session(opts), do: {:ok, opts[:target]}

    def prompt(target, prompt) do
      send(target, {:entered, prompt, self()})

      receive do
        {:finish, text} -> {:ok, [GenAgent.Event.new(:result, %{text: text})], target}
        :fail -> {:error, :isolated_failure}
      end
    end

    def update_session(s, _), do: s
    def terminate_session(_), do: :ok
  end

  # A gated Ensemble boundary, using the real Invocations recipient/eviction path.
  defmodule GatedEnsemble do
    use GenServer

    def start_link(opts),
      do:
        GenServer.start_link(__MODULE__, opts,
          name: {:via, Registry, {GenAgentEnsemble.Registry, opts[:name]}}
        )

    def init(opts), do: {:ok, %{target: opts[:target], entries: [], hold: false, n: 0}}
    def handle_call(:status, _, s), do: {:reply, {:ok, %{agents: [], strategy: __MODULE__}}, s}

    def handle_call({:tell, prompt, opts}, from, s) do
      token = "token-#{s.n}"
      send(s.target, {:tell, from, token, prompt, opts})

      if s.hold,
        do: {:noreply, %{s | n: s.n + 1}},
        else: {:reply, {:ok, token}, %{s | n: s.n + 1}}
    end

    def handle_call({:hold, hold}, _, s), do: {:reply, :ok, %{s | hold: hold}}
    def handle_call({:entries, entries}, _, s), do: {:reply, :ok, %{s | entries: entries}}
    def handle_call(:inbox, _, s), do: {:reply, {:ok, s.entries}, %{s | entries: []}}

    def handle_call({:cancel, token}, from, s) do
      send(s.target, {:cancel_called, from, token})
      {:noreply, s}
    end
  end

  defp name, do: "controller-#{System.unique_integer([:positive])}"

  defp spec(prompt \\ "hello", changes \\ %{}) do
    Map.merge(
      %{
        stage: "work",
        kind: :work,
        provider: "echo",
        requested_settings: %{},
        instruction_revision: "v1",
        checkout: File.cwd!(),
        prompt: prompt
      },
      changes
    )
  end

  defp ledger(names, limits \\ []) do
    l = start_supervised!({Ledger, limits: limits})

    {:ok, run} =
      Ledger.open(l, %{
        name: "run",
        control_revision: "v1",
        tasks: Enum.map(names, &%{name: &1, checkout: File.cwd!(), required_checks: []})
      })

    {l, run}
  end

  defp controller(name, l, run, limits \\ []) do
    start_supervised!({Controller, instance: name, ledger: l, run: run, limits: limits})
  end

  defp instance(names, opts \\ []) do
    n = name()

    {:ok, _} =
      GenAgentServer.create_instance(n, %{
        "cwd" => File.cwd!(),
        "routes" => Enum.map(names, &%{"name" => &1, "provider" => "echo"}),
        "max_in_flight" => Keyword.get(opts, :max_in_flight, 8),
        "max_results" => 1
      })

    on_exit(fn -> GenAgentServer.stop_instance(n) end)
    n
  end

  defp gated do
    n = name()
    e = start_supervised!({GatedEnsemble, name: n, target: self()})

    description = %{
      configured: true,
      routes: [%{name: "worker", provider: "echo", cwd: File.cwd!(), model: nil, effort: nil}]
    }

    owner =
      start_supervised!(
        {GenAgentServer.Invocations,
         name: n,
         agents: [],
         routes: ["worker"],
         strategy: GatedEnsemble,
         max_in_flight: 8,
         max_results: 1,
         poll_interval_ms: 5,
         description: description}
      )

    {n, e, owner}
  end

  defp eventually(fun, n \\ 200)
  defp eventually(fun, 0), do: flunk("condition did not become true: #{inspect(fun.())}")

  defp eventually(fun, n) do
    case fun.() do
      false ->
        Process.sleep(5)
        eventually(fun, n - 1)

      nil ->
        Process.sleep(5)
        eventually(fun, n - 1)

      value ->
        value
    end
  end

  defp attempt(c, id) do
    {:ok, s} = Controller.status(c)
    s.attempts[id]
  end

  defp finished(c, id), do: eventually(fn -> attempt(c, id).terminal end)

  # Stopping a peer waits for the supervisor, not this controller's monitor.
  defp snapshot_when(c, predicate) do
    eventually(fn ->
      {:ok, snapshot} = Controller.status(c)
      if predicate.(snapshot), do: snapshot
    end)
  end

  setup do
    previous = Application.get_env(:gen_agent_server, :provider_overrides)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:gen_agent_server, :provider_overrides, previous),
        else: Application.delete_env(:gen_agent_server, :provider_overrides)
    end)

    :ok
  end

  test "three real Echo tasks retain repeat reads after raw eviction" do
    names = ["a", "b", "c"]
    n = instance(names)
    {l, run} = ledger(names)
    c = controller(n, l, run)

    ids =
      for task <- names do
        assert {:ok, id} = Controller.submit(c, task, task, spec(task))
        id
      end

    for id <- ids, do: assert(finished(c, id).status == :completed)
    {:ok, snapshot} = Controller.result(c)
    assert Controller.result(c) == {:ok, snapshot}
    assert Controller.status(c) == {:ok, snapshot}
    raw = Enum.map(ids, &GenAgentServer.result(n, snapshot.attempts[&1].invocation_id))
    assert Enum.count(raw, &(&1 == {:error, :not_found})) == 2
    {:ok, stored} = Ledger.result(l, run)

    for id <- ids do
      a = snapshot.attempts[id]
      assert a.terminal.text == "echo: #{a.task}"
      assert a.terminal.actual_model == nil
      assert stored.attempts[id].terminal == a.terminal
    end

    assert stored.reserved_bytes == 0
    assert Controller.child_spec([]).restart == :temporary
  end

  test "real gated workers isolate a failure and explicit cancellation" do
    Application.put_env(:gen_agent_server, :provider_overrides, %{
      "echo" => [backend: GatedBackend, target: self()]
    })

    n = instance(["a", "b", "c"])
    {l, run} = ledger(["a", "b", "c"])
    c = controller(n, l, run)
    {:ok, a} = Controller.submit(c, "a", "a", spec("failure"))
    {:ok, b} = Controller.submit(c, "b", "b", spec("success"))
    {:ok, d} = Controller.submit(c, "c", "c", spec("cancel"))
    assert_receive {:entered, "failure", wa}
    assert_receive {:entered, "success", wb}
    assert_receive {:entered, "cancel", _}
    eventually(fn -> attempt(c, d).invocation_id end)
    assert Controller.cancel(c, d) == {:ok, :requested}
    send(wa, :fail)
    send(wb, {:finish, "done"})
    assert finished(c, a).status == :failed
    assert finished(c, b).text == "done"
    assert finished(c, d).status == :cancelled
    eventually(fn -> attempt(c, d).cancel == {:ok, :cancelled} end)
    assert Controller.cancel(c, d) == {:ok, {:ok, :cancelled}}
    assert Controller.cancel(c, b) == {:error, :already_finished}
  end

  test "invalid inputs, conflicts and hard quotas have no invocation side effect" do
    {n, e, _} = gated()
    {l, run} = ledger(["a", "b"])
    c = controller(n, l, run, unfinished: 1, retained: 1)

    for {task, route, s} <- [
          {"a", "worker", spec("x", %{kind: :review})},
          {"a", "worker", spec("x", %{checkout: "/elsewhere"})},
          {"missing", "worker", spec()},
          {"a", "missing", spec()},
          {"a", "worker", spec("x", %{provider: "codex"})},
          {"a", "worker", spec("x", %{requested_settings: %{"model" => "invented"}})},
          {"a", "worker", %{arbitrary: true}}
        ] do
      assert {:error, _} = Controller.submit(c, task, route, s)
    end

    refute_receive {:tell, _, _, _, _}, 0
    assert {:ok, before} = Ledger.result(l, run)
    assert map_size(before.attempts) == 0
    assert {:ok, a} = Controller.submit(c, "a", "worker", spec())
    assert_receive {:tell, _, token, _, opts}
    assert opts == []
    assert Controller.submit(c, "a", "worker", spec()) == {:ok, a}
    assert Controller.submit(c, "a", "worker", spec("changed")) == {:error, :conflict}
    assert Controller.submit(c, "b", "worker", spec()) == {:error, :busy}
    refute_receive {:tell, _, _, _, _}, 0
    :ok = GenServer.call(e, {:entries, [{token, {:ok, %{text: "done"}}}]})
    finished(c, a)
    assert Controller.submit(c, "b", "worker", spec()) == {:error, :busy}

    assert {:error, _} =
             start_supervised(
               {Controller, [instance: n, ledger: l, run: run, limits: [unfinished: 9]]},
               id: :invalid_controller
             )
  end

  test "reservation rejection precedes invocation" do
    {n, _, _} = gated()
    {l, run} = ledger(["a"], records_per_run: 2)
    c = controller(n, l, run)
    assert Controller.submit(c, "a", "worker", spec()) == {:error, :quota_exhausted}
    refute_receive {:tell, _, _, _, _}, 0
    assert {:ok, %{attempts: attempts}} = Ledger.result(l, run)
    assert attempts == %{}
  end

  test "slow admission stays responsive; timeout is uncertainty and late completion correlates" do
    {n, e, owner} = gated()
    :ok = GenServer.call(e, {:hold, true})
    {l, run} = ledger(["a", "b"])
    c = controller(n, l, run, helpers: 1, unfinished: 1)
    {:ok, a} = Controller.submit(c, "a", "worker", spec())
    assert_receive {:tell, from, token, _, _}
    assert {:ok, %{unfinished: 1}} = GenServer.call(c, :snapshot, 1_000)
    [h] = :sys.get_state(c).helpers |> Map.values()
    assert Process.alive?(h.pid)
    # Trigger the real timer path only after proving reads work while admission
    # is held. No race against a tiny wall-clock deadline is needed.
    [tag] = Map.keys(:sys.get_state(c).helpers)
    assert Controller.submit(c, "b", "worker", spec()) == {:error, :busy}
    send(c, {:helper_timeout, tag})
    eventually(fn -> attempt(c, a).execution == :unobserved end)
    assert attempt(c, a).terminal == nil
    assert Controller.cancel(c, a) == {:error, :not_admitted}
    assert {:ok, stored} = Ledger.result(l, run)
    assert stored.attempts[a].terminal == nil
    GenServer.reply(from, {:ok, token})
    :ok = GenServer.call(e, {:entries, [{token, {:ok, %{text: "late"}}}]})
    # The admission helper has died, so only recipient_ref can attribute this.
    assert finished(c, a).text == "late"
    assert Process.alive?(owner)
    assert Controller.cancel(c, a) == {:error, :already_finished}
  end

  test "completion before admission helper reply and helper crash preserve truth" do
    {n, e, owner} = gated()
    :ok = GenServer.call(e, {:hold, true})
    {l, run} = ledger(["a"])
    c = controller(n, l, run)
    {:ok, a} = Controller.submit(c, "a", "worker", spec())
    assert_receive {:tell, from, token, _, _}
    [h] = :sys.get_state(c).helpers |> Map.values()
    :erlang.suspend_process(h.pid)
    GenServer.reply(from, {:ok, token})
    :ok = GenServer.call(e, {:entries, [{token, {:ok, %{text: "first"}}}]})
    assert finished(c, a).text == "first"
    Process.exit(h.pid, :kill)
    assert finished(c, a).text == "first"
    assert Process.alive?(owner)
  end

  test "definite raw busy rejection is retained as admission_failed" do
    # Hold Invocations admission with a pending turn through the gated Ensemble.
    {n2, _, _} = gated()
    [{owner, _}] = Registry.lookup(GenAgentServer.Registry, {:invocations, n2})
    :sys.replace_state(owner, &%{&1 | max_in_flight: 1})
    {:ok, _} = GenAgentServer.invoke(n2, "worker", "occupy")
    assert_receive {:tell, _, _, "occupy", _}
    {l, run} = ledger(["a"])
    c = controller(n2, l, run)
    {:ok, a} = Controller.submit(c, "a", "worker", spec())
    assert finished(c, a).status == :admission_failed
    assert finished(c, a).failure == ":busy"
    refute_receive {:tell, _, _, "hello", _}, 0
  end

  test "held cancellation acknowledgement is separate; terminal wins late completion" do
    {n, e, owner} = gated()
    {l, run} = ledger(["a"])
    c = controller(n, l, run)
    {:ok, a} = Controller.submit(c, "a", "worker", spec())
    assert_receive {:tell, _, token, _, _}
    inv = eventually(fn -> attempt(c, a).invocation_id end)
    assert Controller.cancel(c, a) == {:ok, :requested}
    assert_receive {:cancel_called, from, ^token}
    assert {:ok, _} = GenServer.call(c, :snapshot, 1_000)
    [tag] = Map.keys(:sys.get_state(c).helpers)
    h = :sys.get_state(c).helpers[tag]
    assert Process.alive?(h.pid)
    send(c, {:helper_timeout, tag})
    eventually(fn -> attempt(c, a).cancel == :uncertain end)
    assert attempt(c, a).terminal == nil
    GenServer.reply(from, {:ok, :cancelled_unconfirmed})
    :ok = GenServer.call(e, {:entries, [{token, {:ok, %{text: "authoritative"}}}]})
    assert finished(c, a).text == "authoritative"
    :ok = GenServer.call(e, {:entries, [{token, {:error, :cancelled}}]})
    assert GenAgentServer.result(n, inv) == {:ok, :completed, %{text: "authoritative"}}
    assert finished(c, a).text == "authoritative"
    assert Process.alive?(owner)
  end

  test "owner lifetime loss fences replacement and preserves finished evidence" do
    {n, e, owner} = gated()
    {l, run} = ledger(["a", "b"])
    c = controller(n, l, run)
    {:ok, a} = Controller.submit(c, "a", "worker", spec())
    assert_receive {:tell, _, token, _, _}
    :ok = GenServer.call(e, {:entries, [{token, {:ok, %{text: "done"}}}]})
    finished(c, a)
    {:ok, b} = Controller.submit(c, "b", "worker", spec())
    assert_receive {:tell, _, _, _, _}
    assert :ok = stop_supervised(GenAgentServer.Invocations)
    refute Process.alive?(owner)
    eventually(fn -> attempt(c, b).execution == :unobserved end)
    assert finished(c, a).text == "done"
    assert attempt(c, b).terminal == nil
    # Fresh process registered under the identical owner name cannot be attached.
    {:ok, replacement} =
      GenAgentServer.Invocations.start_link(
        name: n,
        agents: [],
        routes: ["worker"],
        strategy: GatedEnsemble,
        max_in_flight: 8,
        max_results: 1,
        poll_interval_ms: 5,
        description: %{
          configured: true,
          routes: [%{name: "worker", provider: "echo", cwd: File.cwd!()}]
        }
      )

    on_exit(fn -> if Process.alive?(replacement), do: GenServer.stop(replacement) end)
    assert Controller.submit(c, "b", "worker", spec()) == {:ok, b}

    assert Controller.submit(c, "b", "worker", spec("next", %{stage: "next"})) ==
             {:error, :owner_unavailable}

    assert Controller.cancel(c, b) == {:error, :owner_unavailable}
    refute_receive {:tell, _, _, "next", _}, 0
    assert Process.alive?(l)
  end

  test "ledger loss and controller shutdown do not stop shared owners; owned helpers die" do
    {n, e, owner} = gated()
    :ok = GenServer.call(e, {:hold, true})
    {l, run} = ledger(["a"])
    c = controller(n, l, run)
    {:ok, a} = Controller.submit(c, "a", "worker", spec())
    assert_receive {:tell, _, _, _, _}
    [h] = :sys.get_state(c).helpers |> Map.values()
    monitor = Process.monitor(h.pid)
    GenServer.stop(l)
    assert_receive {:DOWN, ^monitor, :process, _, _}
    eventually(fn -> attempt(c, a).execution == :unobserved end)
    assert {:ok, %{unavailable: :ledger_lost}} = Controller.status(c)
    GenServer.stop(c)
    assert Process.alive?(owner)
    assert Process.alive?(e)
  end

  test "bounded text, nil and empty stay distinct; oversized payloads are not retained" do
    {n, e, _} = gated()
    {l, run} = ledger(["a", "b", "c", "d"])
    c = controller(n, l, run, text_bytes: 4)

    for {task, text} <- [{"a", nil}, {"b", ""}, {"c", "éé"}, {"d", "ééé"}] do
      {:ok, id} = Controller.submit(c, task, "worker", spec())
      assert_receive {:tell, _, token, _, _}

      :ok =
        GenServer.call(
          e,
          {:entries,
           [
             {token,
              {:ok,
               %{
                 text: text,
                 events: [String.duplicate("x", 100_000)],
                 metadata: %{model: "requested"}
               }}}
           ]}
        )

      if task == "d" do
        eventually(fn -> attempt(c, id).evidence_error end)
        a = attempt(c, id)
        assert a.terminal == nil
        assert a.text_bytes == 6
        assert a.text_sha256 == Base.encode16(:crypto.hash(:sha256, text), case: :lower)
        assert a.evidence_error == :output_not_retainable
        {:ok, stored} = Ledger.result(l, run)
        assert stored.attempts[id].terminal == nil
      else
        assert finished(c, id).text == text
        assert finished(c, id).actual_model == nil
      end
    end

    assert :erlang.external_size(:sys.get_state(c)) < 12_000
  end

  test "admission helper crash remains unfinished until authoritative completion" do
    {n, e, _} = gated()
    :ok = GenServer.call(e, {:hold, true})
    {l, run} = ledger(["a"])
    c = controller(n, l, run)
    {:ok, a} = Controller.submit(c, "a", "worker", spec())
    assert_receive {:tell, from, token, _, _}
    [h] = :sys.get_state(c).helpers |> Map.values()
    Process.exit(h.pid, :kill)
    eventually(fn -> attempt(c, a).execution == :unobserved end)
    assert attempt(c, a).terminal == nil
    assert Controller.submit(c, "a", "worker", spec()) == {:ok, a}
    refute_receive {:tell, _, _, _, _}, 0
    GenServer.reply(from, {:ok, token})
    :ok = GenServer.call(e, {:entries, [{token, {:ok, %{text: "observed"}}}]})
    assert finished(c, a).text == "observed"
  end

  test "unsupported cancellation and positive acknowledgement do not fabricate terminals" do
    {n, e, _} = gated()
    {l, run} = ledger(["a", "b"])
    c = controller(n, l, run)

    for {task, reply} <- [{"a", {:error, :unsupported}}, {"b", {:ok, :cancelled_unconfirmed}}] do
      {:ok, a} = Controller.submit(c, task, "worker", spec())
      assert_receive {:tell, _, token, _, _}
      eventually(fn -> attempt(c, a).invocation_id end)
      assert Controller.cancel(c, a) == {:ok, :requested}
      assert_receive {:cancel_called, from, ^token}
      GenServer.reply(from, reply)
      eventually(fn -> attempt(c, a).cancel != :requested end)
      assert attempt(c, a).terminal == nil
      assert attempt(c, a).execution == :pending
      observed = attempt(c, a).cancel
      assert Controller.cancel(c, a) == {:ok, observed}
      refute_receive {:cancel_called, _, _}, 0
      :ok = GenServer.call(e, {:entries, [{token, {:ok, %{text: "completion"}}}]})
      assert finished(c, a).text == "completion"
    end
  end

  test "controller shutdown kills a blocked helper without stopping shared resources" do
    {n, e, owner} = gated()
    :ok = GenServer.call(e, {:hold, true})
    {l, run} = ledger(["a"])
    c = controller(n, l, run)
    {:ok, a} = Controller.submit(c, "a", "worker", spec())
    assert_receive {:tell, _, _, _, _}
    [h] = :sys.get_state(c).helpers |> Map.values()
    monitor = Process.monitor(h.pid)
    GenServer.stop(c)
    assert_receive {:DOWN, ^monitor, :process, _, _}
    assert Process.alive?(owner)
    assert Process.alive?(e)
    assert Process.alive?(l)
    {:ok, stored} = Ledger.result(l, run)
    assert stored.attempts[a].terminal == nil
  end

  @tag :lifecycle_review
  test "oversized observed completion survives ledger then owner loss without a terminal" do
    {n, e, owner} = gated()
    {l, run} = ledger(["a"])
    c = controller(n, l, run, text_bytes: 4, unfinished: 1)
    {:ok, a} = Controller.submit(c, "a", "worker", spec())
    assert_receive {:tell, _, token, _, _}
    :ok = GenServer.call(e, {:entries, [{token, {:ok, %{text: "oversized"}}}]})
    eventually(fn -> attempt(c, a).evidence_error == :output_not_retainable end)
    observed = attempt(c, a)
    assert observed.execution == :completed
    assert observed.terminal == nil
    {:ok, stored} = Ledger.result(l, run)
    assert stored.attempts[a].terminal == nil
    assert stored.attempts[a].reserved_bytes > 0
    assert :ok = stop_supervised(Ledger)
    after_ledger = snapshot_when(c, &(&1.ledger_unavailable == :ledger_lost))
    assert after_ledger.attempts[a] == observed
    assert after_ledger.ledger_unavailable == :ledger_lost
    assert :ok = stop_supervised(GenAgentServer.Invocations)
    refute Process.alive?(owner)
    after_owner = snapshot_when(c, & &1.owner_lost)
    assert after_owner.owner_lost
    assert after_owner.attempts[a] == observed
    assert after_owner.unfinished == 1
  end

  @tag :lifecycle_review
  test "ledger loss still permits one bounded same-owner completion, then fences owner loss" do
    {n, e, _} = gated()
    {l, run} = ledger(["a", "b"])
    c = controller(n, l, run)
    {:ok, a} = Controller.submit(c, "a", "worker", spec())
    assert_receive {:tell, _, ta, _, _}
    {:ok, b} = Controller.submit(c, "b", "worker", spec())
    assert_receive {:tell, _, tb, _, _}
    eventually(fn -> attempt(c, b).invocation_id end)
    refs = :sys.get_state(c).attempts
    :ok = stop_supervised(Ledger)
    lost = snapshot_when(c, &(&1.ledger_unavailable == :ledger_lost))
    assert lost.attempts[a].execution == :unobserved
    text = "same lifetime"
    :ok = GenServer.call(e, {:entries, [{ta, {:ok, %{text: text}}}]})
    eventually(fn -> attempt(c, a).execution == :completed end)
    observed = attempt(c, a)
    assert lost.ledger_unavailable == :ledger_lost
    refute lost.owner_lost
    assert Controller.cancel(c, b) == {:error, :ledger_unavailable}
    assert observed.text_bytes == byte_size(text)
    assert observed.text_sha256 == Base.encode16(:crypto.hash(:sha256, text), case: :lower)
    assert observed.terminal == nil
    assert observed.evidence_error == :ledger_unavailable
    assert {:ok, %{unfinished: 2}} = Controller.status(c)
    # Duplicate and malformed notifications cannot rewrite the observed result.
    metadata = %{instance: n, recipient_ref: refs[a].ref, invocation_id: observed.invocation_id}
    send(c, {:gen_agent_server, :completion, metadata, {:ok, :failed, :cancelled}})
    send(c, {:gen_agent_server, :completion, metadata, :malformed})
    assert attempt(c, a) == observed
    :ok = stop_supervised(GenAgentServer.Invocations)
    both_lost = snapshot_when(c, & &1.owner_lost)
    assert both_lost.owner_lost
    assert both_lost.ledger_unavailable == :ledger_lost
    assert both_lost.unavailable == :ledger_lost
    assert attempt(c, a) == observed
    assert attempt(c, b).execution == :unobserved
    # A replacement owner sends a correlated completion for the pending attempt.
    :ok = :sys.suspend(c)

    replacement =
      start_supervised!(
        {GenAgentServer.Invocations,
         name: n,
         agents: [],
         routes: ["worker"],
         strategy: GatedEnsemble,
         max_in_flight: 8,
         max_results: 1,
         poll_interval_ms: 5}
      )

    assert {:ok, _} =
             GenServer.call(
               replacement,
               {:invoke, "worker", "replacement", [recipient: c, recipient_ref: refs[b].ref]}
             )

    assert_receive {:tell, _, replacement_token, "replacement", _}

    :ok =
      GenServer.call(
        e,
        {:entries,
         [
           {tb, {:ok, %{text: "old late"}}},
           {replacement_token, {:ok, %{text: "replacement late"}}}
         ]}
      )

    GenServer.call(replacement, {:result, "not-found"})
    {:messages, queued} = Process.info(c, :messages)

    assert Enum.any?(queued, fn
             {:gen_agent_server, :completion, %{recipient_ref: ref}, _} -> ref == refs[b].ref
             _ -> false
           end)

    :ok = :sys.resume(c)
    # A correlated old-lifetime notification is fenced as well.
    send(
      c,
      {:gen_agent_server, :completion,
       %{instance: n, recipient_ref: refs[b].ref, invocation_id: refs[b].invocation_id},
       {:ok, :completed, %{text: "old late"}}}
    )

    assert attempt(c, b).execution == :unobserved
    assert attempt(c, b).text_bytes == nil
    assert attempt(c, b).terminal == nil
  end

  @tag :lifecycle_review
  test "observed failures and cancellation survive evidence-store failure and owner loss" do
    {n, e, _} = gated()
    {l, run} = ledger(["a", "b"])
    c = controller(n, l, run)
    {:ok, a} = Controller.submit(c, "a", "worker", spec())
    assert_receive {:tell, _, ta, _, _}
    {:ok, b} = Controller.submit(c, "b", "worker", spec())
    assert_receive {:tell, _, tb, _, _}
    :ok = stop_supervised(Ledger)
    snapshot_when(c, &(&1.ledger_unavailable == :ledger_lost))
    :ok = GenServer.call(e, {:entries, [{ta, {:error, :failure}}, {tb, {:error, :cancelled}}]})
    eventually(fn -> attempt(c, a).execution == :failed end)
    eventually(fn -> attempt(c, b).execution == :cancelled end)
    assert attempt(c, a).terminal == nil
    assert attempt(c, b).terminal == nil
    :ok = stop_supervised(GenAgentServer.Invocations)
    snapshot = snapshot_when(c, & &1.owner_lost)
    assert snapshot.owner_lost
    assert snapshot.attempts[a].execution == :failed
    assert snapshot.attempts[b].execution == :cancelled
    assert snapshot.unfinished == 2
  end

  @tag :lifecycle_review
  test "oversized completion survives owner-only loss with reservation and error unchanged" do
    {n, e, _} = gated()
    {l, run} = ledger(["a"])
    c = controller(n, l, run, text_bytes: 4)
    {:ok, a} = Controller.submit(c, "a", "worker", spec())
    assert_receive {:tell, _, token, _, _}
    :ok = GenServer.call(e, {:entries, [{token, {:ok, %{text: "oversized"}}}]})
    eventually(fn -> attempt(c, a).evidence_error == :output_not_retainable end)
    observed = attempt(c, a)
    :ok = stop_supervised(GenAgentServer.Invocations)
    snapshot = snapshot_when(c, & &1.owner_lost)
    assert snapshot.attempts[a] == observed
    assert snapshot.owner_lost
    assert snapshot.ledger_unavailable == nil
    assert snapshot.unfinished == 1
    {:ok, stored} = Ledger.result(l, run)
    assert stored.attempts[a].terminal == nil
    assert stored.attempts[a].reserved_bytes > 0
  end

  @tag :lifecycle_review
  test "terminal-write exit retains completed, failed and cancelled execution locally" do
    {n, e, _} = gated()
    {l, run} = ledger(["a", "b", "c"])
    c = controller(n, l, run)

    submissions =
      for task <- ["a", "b", "c"] do
        {:ok, id} = Controller.submit(c, task, "worker", spec())
        assert_receive {:tell, _, token, _, _}
        eventually(fn -> attempt(c, id).invocation_id end)
        {id, token}
      end

    [{a, ta}, {b, tb}, {d, td}] = submissions
    inv = attempt(c, a).invocation_id
    :ok = :sys.suspend(c)

    :ok =
      GenServer.call(
        e,
        {:entries,
         [{ta, {:ok, %{text: "done"}}}, {tb, {:error, :failure}}, {td, {:error, :cancelled}}]}
      )

    GenAgentServer.result(n, inv)
    {:messages, queued} = Process.info(c, :messages)
    assert Enum.count(queued, &match?({:gen_agent_server, :completion, _, _}, &1)) == 3
    # Completion messages precede DOWN, but their terminal write encounters the
    # dead ledger. Observed execution must survive the write's exit handler.
    :ok = stop_supervised(Ledger)
    :ok = :sys.resume(c)
    snapshot = snapshot_when(c, &(&1.ledger_unavailable == :ledger_lost))
    assert snapshot.attempts[a].execution == :completed
    assert snapshot.attempts[b].execution == :failed
    assert snapshot.attempts[d].execution == :cancelled

    for {id, _} <- submissions do
      assert snapshot.attempts[id].terminal == nil
      assert snapshot.attempts[id].evidence_error == :ledger_unavailable
    end

    assert snapshot.unfinished == 3
    refute snapshot.owner_lost
    assert snapshot.ledger_unavailable == :ledger_lost
  end

  @tag :lifecycle_review
  test "definite admission rejection survives its terminal-write exit" do
    {n, e, _} = gated()
    :ok = GenServer.call(e, {:hold, true})
    {l, run} = ledger(["a"])
    c = controller(n, l, run)
    {:ok, a} = Controller.submit(c, "a", "worker", spec())
    assert_receive {:tell, from, _, _, _}
    :ok = :sys.suspend(c)
    GenServer.reply(from, {:error, :definite_rejection})

    eventually(fn ->
      {:messages, queued} = Process.info(c, :messages)
      Enum.any?(queued, &match?({:helper, _, {:error, :definite_rejection}}, &1))
    end)

    :ok = stop_supervised(Ledger)
    :ok = :sys.resume(c)
    observed = attempt(c, a)
    assert observed.execution == :admission_failed
    assert observed.evidence_error == :ledger_unavailable
    assert observed.terminal == nil
    :ok = stop_supervised(GenAgentServer.Invocations)
    snapshot_when(c, & &1.owner_lost)
    assert attempt(c, a) == observed
    assert {:ok, %{unfinished: 1}} = Controller.status(c)
  end

  @tag :lifecycle_review
  test "ledger admission-call exit reports ledger availability, never owner death" do
    {n, _, owner} = gated()
    {l, run} = ledger(["a"])
    c = controller(n, l, run)
    :ok = :sys.suspend(c)
    request = make_ref()
    send(c, {:"$gen_call", {self(), request}, {:submit, "a", "worker", spec()}})
    # The submission is queued before ledger death, so it reaches the call exit
    # path before the controller handles the ledger monitor's DOWN signal.
    :ok = stop_supervised(Ledger)
    :ok = :sys.resume(c)
    assert_receive {^request, {:error, :ledger_unavailable}}, 1_000
    snapshot = snapshot_when(c, &(&1.ledger_unavailable == :ledger_lost))
    assert snapshot.ledger_unavailable == :ledger_lost
    refute snapshot.owner_lost
    assert snapshot.attempts == %{}
    assert Process.alive?(owner)
    refute_receive {:tell, _, _, _, _}, 0
  end

  test "encoded metadata overhead cannot exceed the terminal reservation silently" do
    {n, e, _} = gated()
    {l, run} = ledger(["a"], record_bytes: 1024)
    c = controller(n, l, run)
    {:ok, a} = Controller.submit(c, "a", "worker", spec())
    assert_receive {:tell, _, token, _, _}
    text = String.duplicate("x", 1000)
    :ok = GenServer.call(e, {:entries, [{token, {:ok, %{text: text}}}]})
    eventually(fn -> attempt(c, a).evidence_error end)
    assert attempt(c, a).evidence_error == :quota_exhausted
    assert attempt(c, a).terminal == nil
    {:ok, stored} = Ledger.result(l, run)
    assert stored.attempts[a].reserved_bytes == 1024
  end
end

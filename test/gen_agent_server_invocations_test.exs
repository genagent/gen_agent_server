defmodule GenAgentServerInvocationsTest do
  use ExUnit.Case, async: false

  alias GenAgentServer.Ops

  defmodule GatedBackend do
    @behaviour GenAgent.Backend
    def start_session(opts), do: {:ok, opts[:target]}

    def prompt(target, prompt) do
      send(target, {:entered, prompt, self()})

      receive do
        {:release, :ok} ->
          {:ok, [GenAgent.Event.new(:result, %{text: "private response"})], target}

        {:release, reason} ->
          {:error, reason}
      end
    end

    def update_session(session, _), do: session
    def terminate_session(_), do: :ok
  end

  defp instance(backend, opts) do
    name = "summaries-#{System.unique_integer([:positive])}"
    agents = [{"worker", GenAgentEnsemble.Agents.Simple, [backend: backend, target: self()]}]
    assert {:ok, _} = GenAgentServer.start_instance(name, agents, opts)
    on_exit(fn -> GenAgentServer.stop_instance(name) end)
    {name, agents}
  end

  test "gated pending and terminals are isolated, ordered, bounded and content-free" do
    {name, _} = instance(GatedBackend, poll_interval_ms: 60_000)
    {other, _} = instance(GatedBackend, poll_interval_ms: 60_000)
    before_ms = System.system_time(:millisecond)

    assert {:ok, a} =
             GenAgentServer.invoke(name, "worker", "private prompt",
               source: :mcp,
               recipient: self(),
               credential: "private credential"
             )

    assert_receive {:entered, "private prompt", worker}
    assert {:ok, b} = GenAgentServer.invoke(name, "worker", "queued private prompt")
    assert {:ok, [pending_b, pending_a] = pending} = GenAgentServer.invocations(name)
    assert pending_a.id == a and pending_b.id == b
    assert pending_a.route == "worker" and pending_a.source == :mcp
    assert pending_a.status == :pending
    assert pending_a.completed_at_unix_ms == nil and pending_a.duration_ms == nil
    assert pending_a.error_category == nil
    assert pending_a.admitted_at_unix_ms >= before_ms
    assert pending_a.admitted_at_unix_ms <= System.system_time(:millisecond)
    assert {:ok, ^pending} = GenAgentServer.invocations(name)
    assert {:ok, [^pending_b]} = GenAgentServer.invocations(name, limit: 1)
    assert {:ok, []} = GenAgentServer.invocations(other)

    send(worker, {:release, :ok})

    assert eventually(fn ->
             {:ok, summaries} = GenAgentServer.invocations(name)
             Enum.any?(summaries, &(&1.id == a and &1.status == :completed))
           end)

    assert_receive {:gen_agent_server, :completion, %{invocation_id: ^a},
                    {:ok, :completed, %{text: "private response"}}},
                   2_000

    assert_receive {:entered, "queued private prompt", next_worker}
    assert {:ok, [still_pending, done]} = GenAgentServer.invocations(name)
    assert still_pending == pending_b
    assert done.id == a and done.status == :completed and done.error_category == nil
    assert done.duration_ms >= 0
    assert done.completed_at_unix_ms >= before_ms
    assert done.completed_at_unix_ms <= System.system_time(:millisecond)

    assert Map.keys(done) |> Enum.sort() ==
             Enum.sort([
               :id,
               :route,
               :source,
               :status,
               :admitted_at_unix_ms,
               :completed_at_unix_ms,
               :duration_ms,
               :error_category
             ])

    send(next_worker, {:release, {:private_error, "private reason", %{credential: "private"}}})

    assert eventually(fn ->
             {:ok, [summary | _]} = GenAgentServer.invocations(name)
             summary.status == :failed
           end)

    assert {:ok, [failed, ^done] = terminal} = GenAgentServer.invocations(name)
    assert failed.error_category == :backend_error
    assert {:ok, ^terminal} = GenAgentServer.invocations(name)
    assert {:ok, %{invocations: json}} = Ops.call("invocations", %{"instance" => name})
    assert json == Ops.jsonable(terminal)
    encoded = Jason.encode!(json)
    refute encoded =~ "private"
    refute encoded =~ "credential"
    refute encoded =~ "recipient"
    assert {:ok, :failed, _} = GenAgentServer.result(name, b)
  end

  test "cancellation is projected separately without changing result or notification" do
    {name, _} = instance(GatedBackend, poll_interval_ms: 60_000)
    assert {:ok, id} = GenAgentServer.invoke(name, "worker", "cancel", recipient: self())
    assert_receive {:entered, "cancel", _}
    assert {:ok, :cancelled} = GenAgentServer.cancel(name, id)
    assert {:ok, :failed, :cancelled} = GenAgentServer.result(name, id)

    assert_receive {:gen_agent_server, :completion, %{invocation_id: ^id},
                    {:ok, :failed, :cancelled}}

    assert {:ok,
            [%{id: ^id, status: :cancelled, error_category: :cancelled, duration_ms: duration}]} =
             GenAgentServer.invocations(name)

    assert duration >= 0
  end

  test "Echo eviction, default and maximum limits, repeat reads and restart discard" do
    {name, agents} = instance(GenAgentEnsemble.Backends.Echo, max_results: 55)

    ids =
      for n <- 1..56 do
        assert {:ok, id} = GenAgentServer.invoke(name, "worker", "secret #{n}")
        assert eventually(fn -> match?({:ok, :completed, _}, GenAgentServer.result(name, id)) end)
        id
      end

    assert {:ok, default} = GenAgentServer.invocations(name)
    assert length(default) == 50
    assert {:ok, all} = GenAgentServer.invocations(name, limit: 200)
    assert Enum.map(all, & &1.id) == ids |> Enum.drop(1) |> Enum.reverse()
    assert {:ok, ^all} = GenAgentServer.invocations(name, limit: 200)
    assert {:error, :not_found} = GenAgentServer.result(name, hd(ids))
    assert :ok = GenAgentServer.stop_instance(name)
    assert {:error, :instance_not_found} = GenAgentServer.invocations(name)
    assert {:ok, _} = GenAgentServer.start_instance(name, agents)
    assert {:ok, []} = GenAgentServer.invocations(name)
    assert {:error, :not_found} = GenAgentServer.result(name, List.last(ids))
    assert {:error, :instance_not_found} = GenAgentServer.invocations("summaries-unknown")
  end

  test "completion order cannot reorder admissions and eviction retains pending metadata" do
    name = "summaries-order-#{System.unique_integer([:positive])}"

    agents =
      for route <- ["a", "b"],
          do: {route, GenAgentEnsemble.Agents.Simple, [backend: GatedBackend, target: self()]}

    assert {:ok, _} =
             GenAgentServer.start_instance(name, agents,
               max_results: 1,
               max_in_flight: 2,
               poll_interval_ms: 60_000
             )

    on_exit(fn -> GenAgentServer.stop_instance(name) end)
    assert {:ok, a} = GenAgentServer.invoke(name, "a", "first")
    assert_receive {:entered, "first", first}
    assert {:ok, b} = GenAgentServer.invoke(name, "b", "second")
    assert_receive {:entered, "second", second}
    assert {:error, :busy} = GenAgentServer.invoke(name, "b", "rejected")
    send(second, {:release, :ok})
    assert eventually(fn -> match?({:ok, :completed, _}, GenAgentServer.result(name, b)) end)

    assert {:ok, [%{id: ^b, status: :completed}, %{id: ^a, status: :pending}]} =
             GenAgentServer.invocations(name)

    send(first, {:release, :ok})
    assert eventually(fn -> match?({:ok, :completed, _}, GenAgentServer.result(name, a)) end)
    assert {:ok, [%{id: ^a, status: :completed}]} = GenAgentServer.invocations(name)
    assert {:error, :not_found} = GenAgentServer.result(name, b)
  end

  test "failure categories are fixed even when reasons contain private data" do
    {name, _} = instance(GatedBackend, poll_interval_ms: 60_000)

    for {reason, category} <- [
          {:timeout, :timeout},
          {{:task_crashed, "private crash"}, :task_crashed},
          {{:timeout, "private detail"}, :backend_error}
        ] do
      assert {:ok, id} = GenAgentServer.invoke(name, "worker", "private prompt")
      assert_receive {:entered, "private prompt", worker}
      send(worker, {:release, reason})

      assert eventually(fn ->
               {:ok, [summary | _]} = GenAgentServer.invocations(name)
               summary.status == :failed
             end)

      assert {:ok, [%{id: ^id, error_category: ^category} | _]} = GenAgentServer.invocations(name)
      assert {:ok, :failed, ^reason} = GenAgentServer.result(name, id)
    end
  end

  test "Ops CLI parses instance and integer limit and uses the same summary data" do
    {name, _} = instance(GenAgentEnsemble.Backends.Echo, max_results: 2)
    assert {:ok, id} = GenAgentServer.invoke(name, "worker", "private CLI prompt")
    assert eventually(fn -> match?({:ok, :completed, _}, GenAgentServer.result(name, id)) end)

    output =
      ExUnit.CaptureIO.capture_io(fn ->
        Mix.Tasks.GenAgentServer.Ops.run(["invocations", "--instance", name, "--limit", "1"])
      end)

    assert %{"instance" => ^name, "invocations" => [%{"id" => ^id}]} = Jason.decode!(output)
    refute output =~ "private CLI prompt"
  end

  test "invalid limits and arguments return typed errors without admission" do
    for limit <- [0, -1, 201, 1.0, "1", nil, :infinity] do
      assert {:error, :invalid_limit} = GenAgentServer.invocations("unknown", limit: limit)

      assert {:error, %{code: code}} =
               Ops.call("invocations", %{"instance" => "unknown", "limit" => limit})

      assert code in ["invalid_args", "invalid_limit"]
    end

    assert {:error, :invalid_options} = GenAgentServer.invocations("unknown", bogus: 1)
    assert {:error, :invalid_options} = GenAgentServer.invocations("unknown", %{})
    assert {:error, :invalid_options} = GenAgentServer.invocations("unknown", [:limit])
    assert {:error, :invalid_instance} = GenAgentServer.invocations(nil)
    assert {:error, %{code: "invalid_args"}} = Ops.call("invocations", %{})
    assert {:ok, op} = Ops.fetch("invocations")
    refute op.mutates
    assert Ops.json_schema(op)["required"] == ["instance"]
    assert Ops.json_schema(op)["properties"]["limit"]["maximum"] == 200
  end

  defp eventually(fun, attempts \\ 100)
  defp eventually(_, 0), do: false

  defp eventually(fun, attempts) do
    if fun.(),
      do: true,
      else:
        (
          Process.sleep(10)
          eventually(fun, attempts - 1)
        )
  end
end

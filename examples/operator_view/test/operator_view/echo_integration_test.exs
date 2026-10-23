defmodule OperatorView.EchoIntegrationTest do
  # Starts the real server application in this test VM (Echo and gated test
  # backends only, no provider) and reads it through the release's own Ops
  # envelope. The observer itself never starts or calls the server.
  use OperatorView.OperatorCase, async: false

  defmodule GatedBackend do
    @moduledoc false
    @behaviour GenAgent.Backend

    def start_session(opts), do: {:ok, opts[:target]}

    def prompt(target, prompt) do
      send(target, {:entered, prompt, self()})

      receive do
        {:release, :ok} -> {:ok, [GenAgent.Event.new(:result, %{text: "reply"})], target}
        {:release, reason} -> {:error, reason}
      end
    end

    def update_session(session, _opts), do: session
    def terminate_session(_session), do: :ok
  end

  setup_all do
    {:ok, _apps} = Application.ensure_all_started(:gen_agent_server)
    :ok
  end

  setup do
    configure(transport: OperatorView.InProcessTransport, in_process_owner: self())
    :ok
  end

  defp gated_instance do
    name = "observed-#{System.unique_integer([:positive])}"
    backend = [backend: GatedBackend, target: self()]
    agents = [{"worker", GenAgentEnsemble.Agents.Simple, backend}]
    {:ok, _pid} = GenAgentServer.start_instance(name, agents, poll_interval_ms: 60_000)
    on_exit(fn -> GenAgentServer.stop_instance(name) end)
    name
  end

  defp echo_instance(max_results) do
    name = "echo-#{System.unique_integer([:positive])}"
    routes = [%{"name" => "smoke", "provider" => "echo"}]
    config = %{"routes" => routes, "max_results" => max_results}
    {:ok, _description} = GenAgentServer.create_instance(name, config)
    on_exit(fn -> GenAgentServer.stop_instance(name) end)
    {name, config}
  end

  defp run_echo(name, n) do
    {:ok, id} = GenAgentServer.invoke(name, "smoke", "sentinel #{n}")
    assert eventually(fn -> finished?(name, id, :completed) end)
    id
  end

  defp finished?(name, id, status) do
    match?({:ok, ^status, _}, GenAgentServer.result(name, id))
  end

  defp has_row?(view, id, status) do
    has_element?(view, ~s(tr[data-id="#{id}"][data-status="#{status}"]))
  end

  test "pending work becomes terminal on refresh and a reconnect never resubmits" do
    name = gated_instance()
    configure(instances: [name])
    {:ok, id} = GenAgentServer.invoke(name, "worker", "sentinel prompt")
    assert_receive {:entered, "sentinel prompt", worker}

    {:ok, view, _html} = live(operator_conn(), "/?instance=#{name}")
    assert eventually(fn -> has_row?(view, id, "pending") end)

    send(worker, {:release, :ok})
    assert eventually(fn -> finished?(name, id, :completed) end)
    render_click(view, "refresh")
    assert eventually(fn -> has_row?(view, id, "completed") end)

    # A new page (as after a reconnect) reads the same retained summary.
    {:ok, reconnected, _html} = live(operator_conn(), "/?instance=#{name}")
    assert eventually(fn -> has_row?(reconnected, id, "completed") end)

    assert {:ok, [%{id: ^id}]} = GenAgentServer.invocations(name)
    refute_receive {:entered, _prompt, _worker}, 100
    refute render(reconnected) =~ "sentinel"
    assert_only_reads([name])
  end

  test "two instances are observed separately" do
    gated = gated_instance()
    {echo, _config} = echo_instance(10)
    configure(instances: [gated, echo])

    {:ok, pending_id} = GenAgentServer.invoke(gated, "worker", "sentinel one")
    assert_receive {:entered, "sentinel one", _worker}
    echo_id = run_echo(echo, 1)

    {:ok, view, _html} = live(operator_conn(), "/?instance=#{gated}")
    assert eventually(fn -> has_row?(view, pending_id, "pending") end)
    refute render(view) =~ echo_id
    assert render(view) =~ "route names only"

    render_change(view, "select", %{"instance" => echo})
    assert_patch(view, "/?instance=#{echo}")
    assert eventually(fn -> has_row?(view, echo_id, "completed") end)
    refute render(view) =~ pending_id
    assert has_element?(view, ~s(td[data-route-field="provider"]), "echo")
    assert_only_reads([gated, echo])
  end

  test "cancelled and failed summaries show only fixed categories" do
    cancelled_in = gated_instance()
    failed_in = gated_instance()
    configure(instances: [cancelled_in, failed_in])

    {:ok, cancelled} = GenAgentServer.invoke(cancelled_in, "worker", "sentinel cancel")
    assert_receive {:entered, "sentinel cancel", _worker}
    assert {:ok, :cancelled} = GenAgentServer.cancel(cancelled_in, cancelled)

    {:ok, failed} = GenAgentServer.invoke(failed_in, "worker", "sentinel fail")
    assert_receive {:entered, "sentinel fail", worker}
    send(worker, {:release, {:sentinel_reason, "sentinel detail"}})
    assert eventually(fn -> finished?(failed_in, failed, :failed) end)

    {:ok, view, _html} = live(operator_conn(), "/?instance=#{cancelled_in}")
    assert eventually(fn -> has_row?(view, cancelled, "cancelled") end)

    render_change(view, "select", %{"instance" => failed_in})
    assert eventually(fn -> has_row?(view, failed, "failed") end)
    assert render(view) =~ "backend_error"
    refute render(view) =~ "sentinel"
  end

  test "evicted and restarted summaries disappear instead of reading as completed" do
    {name, config} = echo_instance(2)
    configure(instances: [name])
    [first, second, third] = for n <- 1..3, do: run_echo(name, n)

    {:ok, view, _html} = live(operator_conn(), "/?instance=#{name}")
    assert eventually(fn -> has_row?(view, third, "completed") end)
    assert has_row?(view, second, "completed")
    refute render(view) =~ first

    :ok = GenAgentServer.stop_instance(name)
    render_click(view, "refresh")
    assert eventually(fn -> render(view) =~ "Instance not running in the release" end)
    refute render(view) =~ second

    {:ok, _description} = GenAgentServer.create_instance(name, config)
    render_click(view, "refresh")
    assert eventually(fn -> has_element?(view, "#no-invocations") end)
    refute render(view) =~ third
    assert_only_reads([name])
  end
end

defmodule GenAgentServerTelemetryTest do
  use ExUnit.Case, async: false

  @events [
    [:gen_agent_server, :invocation, :start],
    [:gen_agent_server, :invocation, :stop],
    [:gen_agent_server, :invocation, :error],
    [:gen_agent_server, :admission, :rejected],
    [:gen_agent_server, :wait, :timeout]
  ]

  defmodule ErrorBackend do
    @behaviour GenAgent.Backend

    def start_session(_opts), do: {:ok, %{}}
    def prompt(session, _prompt), do: {:error, {:fixture_failure, session}}
    def update_session(session, _event), do: session
    def terminate_session(_session), do: :ok
  end

  setup do
    handler_id = "server-telemetry-test-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach_many(
        handler_id,
        @events,
        &__MODULE__.handle_event/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    :ok
  end

  @doc false
  def handle_event(event, measurements, metadata, target) do
    send(target, {:telemetry, event, measurements, metadata})
  end

  test "success events correlate an invocation without content or duplicate completion" do
    parent = self()

    spawn(fn ->
      send(
        parent,
        {:invocation,
         GenAgentServer.invoke(GenAgentServer.session_name(), "echo", "secret prompt",
           source: :mcp
         )}
      )
    end)

    assert_receive {:invocation, {:ok, id}}

    assert_receive {:telemetry, [:gen_agent_server, :invocation, :start],
                    %{system_time: system_time}, %{invocation_id: ^id} = metadata}

    assert is_integer(system_time)
    assert metadata.instance == GenAgentServer.session_name()
    assert metadata.agent == "echo"
    assert metadata.source == :mcp
    assert is_binary(metadata.ensemble_token)
    refute Map.has_key?(metadata, :prompt)
    refute Map.has_key?(metadata, :response)

    assert {:ok, :completed, %{text: "echo: secret prompt"}} = await_result(id)

    assert_receive {:telemetry, [:gen_agent_server, :invocation, :stop], %{duration_ms: duration},
                    %{invocation_id: ^id} = stop_metadata}

    assert is_integer(duration) and duration >= 0
    assert stop_metadata == metadata
    assert {:ok, :completed, _} = GenAgentServer.result(id)

    refute_receive {:telemetry, [:gen_agent_server, :invocation, :stop], _,
                    %{invocation_id: ^id}},
                   50
  end

  test "remote CLI expression labels its invocation source" do
    expression = GenAgentServer.Remote.expression(["invoke", "echo", "remote"])
    id = ExUnit.CaptureIO.capture_io(fn -> Code.eval_string(expression) end) |> String.trim()

    assert_receive {:telemetry, [:gen_agent_server, :invocation, :start], _,
                    %{invocation_id: ^id, source: :remote_cli}}

    assert {:ok, :completed, %{text: "echo: remote"}} = await_result(id)
  end

  test "failure telemetry has a bounded error kind and repeated result reads" do
    name = "telemetry-error-#{System.unique_integer([:positive])}"
    agents = [{"broken", GenAgentEnsemble.Agents.Simple, [backend: ErrorBackend]}]
    assert {:ok, _pid} = GenAgentServer.start_instance(name, agents)
    on_exit(fn -> GenAgentServer.stop_instance(name) end)

    assert {:ok, id} = GenAgentServer.invoke(name, "broken", "secret")

    assert_receive {:telemetry, [:gen_agent_server, :invocation, :start], _,
                    %{invocation_id: ^id}}

    assert {:ok, :failed, reason} = await_result(name, id)
    assert reason == {:fixture_failure, %{}}

    assert_receive {:telemetry, [:gen_agent_server, :invocation, :error],
                    %{duration_ms: duration}, %{invocation_id: ^id} = metadata}

    assert is_integer(duration) and duration >= 0
    assert metadata.error_kind == :backend_error
    refute Map.has_key?(metadata, :reason)
    assert {:ok, :failed, ^reason} = GenAgentServer.result(name, id)
  end

  test "rejected admission has no invocation ID" do
    assert {:error, {:unknown_agent, "missing"}} = GenAgentServer.invoke("missing", "secret")

    assert_receive {:telemetry, [:gen_agent_server, :admission, :rejected], %{system_time: _},
                    metadata}

    assert metadata.reason == :unknown_agent
    assert metadata.source == :api
    refute Map.has_key?(metadata, :invocation_id)
    refute Map.has_key?(metadata, :prompt)
  end

  test "caller timeout is distinct from eventual invocation completion" do
    name = "telemetry-timeout-#{System.unique_integer([:positive])}"

    agents = [
      {"slow", GenAgentEnsemble.Agents.Simple,
       [backend: GenAgentEnsemble.Backends.Echo, delay_ms: 100]}
    ]

    assert {:ok, _pid} = GenAgentServer.start_instance(name, agents)
    on_exit(fn -> GenAgentServer.stop_instance(name) end)

    assert {:error, :timeout} =
             GenAgentServer.ask_instance(name, "slow", "hello", timeout: 0)

    assert_receive {:telemetry, [:gen_agent_server, :invocation, :start], _, %{invocation_id: id}}

    assert_receive {:telemetry, [:gen_agent_server, :wait, :timeout], %{duration_ms: wait_ms},
                    %{invocation_id: ^id}}

    assert is_integer(wait_ms) and wait_ms >= 0
    assert {:ok, :completed, %{text: "echo: hello"}} = await_result(name, id)
    assert_receive {:telemetry, [:gen_agent_server, :invocation, :stop], _, %{invocation_id: ^id}}
  end

  defp await_result(id), do: await_result(GenAgentServer.session_name(), id)

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

defmodule GenAgentServer.Telemetry do
  @moduledoc """
  Content-free invocation telemetry for the server control API.

  Events:

    * `[:gen_agent_server, :invocation, :start]` — admitted turn; measurement
      `system_time` uses the VM native time unit.
    * `[:gen_agent_server, :invocation, :stop]` — completed turn; measurement
      `duration_ms` is elapsed milliseconds since admission.
    * `[:gen_agent_server, :invocation, :error]` — failed or cancelled turn; the same
      `duration_ms` measurement and a bounded `error_kind` category.
    * `[:gen_agent_server, :admission, :rejected]` — request not admitted,
      with a bounded `reason` category and no invocation ID.
    * `[:gen_agent_server, :wait, :timeout]` — a synchronous caller stopped
      waiting; the invocation itself may still complete later.

  Invocation metadata contains `instance`, `agent`, `invocation_id`,
  `ensemble_token`, and `source`.
  Cancellation errors use `error_kind: :cancelled` and may include
  `cancellation_ack: :cancelled | :cancelled_unconfirmed`.
  It never includes prompts, responses, backend state, or raw error terms.
  IDs and names are correlation fields,
  not suitable as metric labels.
  """

  @prefix [:gen_agent_server]

  def start(metadata) do
    :telemetry.execute(
      @prefix ++ [:invocation, :start],
      %{system_time: System.system_time()},
      metadata
    )
  end

  def stop(metadata, started_at_ms) do
    :telemetry.execute(
      @prefix ++ [:invocation, :stop],
      %{duration_ms: elapsed_ms(started_at_ms)},
      metadata
    )
  end

  def error(metadata, started_at_ms, reason) do
    :telemetry.execute(
      @prefix ++ [:invocation, :error],
      %{duration_ms: elapsed_ms(started_at_ms)},
      Map.put(metadata, :error_kind, error_kind(reason))
    )
  end

  def rejected(instance, agent, source, reason) do
    :telemetry.execute(
      @prefix ++ [:admission, :rejected],
      %{system_time: System.system_time()},
      %{instance: instance, agent: agent, source: source, reason: rejection_kind(reason)}
    )
  end

  def wait_timeout(instance, agent, id, source, started_at_ms) do
    :telemetry.execute(
      @prefix ++ [:wait, :timeout],
      %{duration_ms: elapsed_ms(started_at_ms)},
      %{instance: instance, agent: agent, invocation_id: id, source: source}
    )
  end

  defp elapsed_ms(started_at_ms), do: max(System.monotonic_time(:millisecond) - started_at_ms, 0)

  defp error_kind(:timeout), do: :timeout
  defp error_kind(:cancelled), do: :cancelled
  defp error_kind({:task_crashed, _}), do: :task_crashed
  defp error_kind(_), do: :backend_error

  defp rejection_kind({:unknown_agent, _}), do: :unknown_agent
  defp rejection_kind(:busy), do: :busy
  defp rejection_kind(:invalid_source), do: :invalid_source
  defp rejection_kind(:invalid_recipient), do: :invalid_recipient
  defp rejection_kind(_), do: :admission_error
end

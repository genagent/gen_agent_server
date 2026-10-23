defmodule OperatorView.InProcessTransport do
  @moduledoc false
  # Runs the release's own Ops envelope (GenAgentServer.Ops.Remote.main/2) in
  # this VM, against a server application the integration tests start, and
  # decodes its last output line as Ops.Remote.call/4 does. Each operation is
  # reported to the test process named by the :in_process_owner setting.

  @behaviour OperatorView.Transport

  @impl true
  def call(operation, args, _timeout_ms) do
    report(operation, args)
    json = Jason.encode!(args)
    main = fn -> GenAgentServer.Ops.Remote.main(operation, json) end
    lines = main |> ExUnit.CaptureIO.capture_io() |> String.trim() |> String.split("\n")

    case Jason.decode(List.last(lines)) do
      {:ok, %{"ok" => true, "data" => data}} -> {:ok, data}
      {:ok, %{"ok" => false, "error" => error}} -> {:error, error}
      _other -> {:error, %{code: "rpc_bad_output"}}
    end
  end

  defp report(operation, args) do
    case Application.get_env(:operator_view, :in_process_owner) do
      pid when is_pid(pid) -> send(pid, {:release_call, operation, args})
      _none -> :ok
    end
  end
end

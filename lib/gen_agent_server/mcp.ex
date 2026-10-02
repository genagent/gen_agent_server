defmodule GenAgentServer.MCP do
  @moduledoc """
  Local stdio MCP adapter over `GenAgentServer.Ops`.

  The catalogue is an allowlist: `instances`, `agents`, `status`, `invoke`,
  `result`, `ask`, and the lifecycle tools `create_instance`,
  `describe_instance`, and `stop_instance`, plus read-only public GitHub
  source tools `public_revision`, `public_file`, `public_issues`, and `public_issue`.
  Every other operation, including
  `run_pattern`, jobs, and arbitrary pattern specs, stays unreachable from MCP.
  `invoke` and `ask` record telemetry source `:mcp`.

  Lifecycle workflow for a client that manages its own agents:

    1. `create_instance` with a name and routes, each with a provider
       (`echo`, `claude`, `codex`) and optionally a model and effort. Claude
       defaults to a limited read-only toolset and Codex to a read-only sandbox;
       edit modes are explicit per-route opt-ins. Configuration is fixed at
       creation; to change a model, create another instance.
    2. `describe_instance` returns each route's provider, model, effort, mode,
       and cwd, and the instance's `max_in_flight` and `max_results` limits.
       Call it after reconnecting to discover what exists.
    3. `invoke` (or `ask`) a route, then read `result`, which is repeatable
       until evicted.
    4. `stop_instance` discards the instance and its stored results. The
       default instance cannot be stopped.

  Instances and results live in this process's VM only. Creation is volatile:
  closing stdin, or starting a new stdio process, loses them, and the new
  process does not reconnect to the old one's store.

  Run it with `mix gen_agent_server.mcp` from a checkout or
  `bin/gen_agent_server eval "GenAgentServer.MCP.serve()"` from a release. The
  MCP process is its own VM: it hosts its own instances and results, which last
  for the life of the MCP session.

  After `serve/0` starts, stdout carries only MCP protocol messages. Logger
  output goes to stderr.
  """

  alias GenAgentServer.Ops

  @tools ~w(instances agents status invoke result ask create_instance describe_instance stop_instance public_revision public_file public_issues public_issue)

  @doc "Names of the operations exposed over MCP."
  def tools, do: @tools

  @doc false
  def run(name, arguments) when name in @tools do
    case Ops.call(name, arguments || %{}, source: :mcp) do
      {:ok, data} ->
        {:ok, data |> Jason.encode!() |> Jason.decode!() |> Snodo.Result.structured()}

      {:error, %{code: code, message: message}} ->
        {:ok, Snodo.Result.error("#{code}: #{message}")}
    end
  end

  @doc """
  Start the application and serve MCP over stdin/stdout until stdin closes.
  """
  def serve do
    stdout_to_protocol_only()
    {:ok, _} = Application.ensure_all_started(:gen_agent_server)
    # A caller may ask for a longer wait than Snodo's default execution
    # deadline. GenAgentServer.Ops owns the ask timeout and the underlying
    # GenAgent watchdog bounds provider work.
    Snodo.Transport.Stdio.serve(GenAgentServer.MCP.Server.runtime(),
      request_timeout: :infinity
    )
  end

  # The default Logger handler writes to stdout, which would corrupt the
  # protocol stream. Move it to stderr before any application starts.
  defp stdout_to_protocol_only do
    with {:ok, %{module: module, config: %{type: :standard_io}} = config} <-
           :logger.get_handler_config(:default) do
      :ok = :logger.remove_handler(:default)

      handler =
        config
        |> Map.take([:level, :filter_default, :filters, :formatter])
        |> Map.put(:config, %{type: :standard_error})

      :ok = :logger.add_handler(:default, module, handler)
    end

    :ok
  end
end

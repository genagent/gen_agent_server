defmodule GenAgentServer do
  @moduledoc """
  Local control API for this runnable GenAgent application.

  Each instance owns an Ensemble session and a bounded, non-destructive
  invocation result store. Results survive the submitting caller but not an
  instance or VM restart. Pattern instances can use another Ensemble strategy
  with one external route; each configured backend keeps its own session.
  """

  def session_name, do: Application.fetch_env!(:gen_agent_server, :session_name)

  def instances do
    Registry.select(GenAgentServer.Registry, [
      {{{:instance, :"$1"}, :_, :_}, [], [:"$1"]}
    ])
    |> Enum.sort()
  end

  def start_instance(name, agents, opts \\ [])
      when is_binary(name) and is_list(agents) and is_list(opts) do
    DynamicSupervisor.start_child(
      GenAgentServer.InstanceSupervisor,
      {GenAgentServer.Instance, Keyword.merge(opts, name: name, agents: agents)}
    )
  end

  @doc "Start a managed Ensemble pattern with one external invocation route."
  def start_pattern_instance(name, route, strategy, strategy_opts, opts \\ [])
      when is_binary(name) and is_binary(route) and route != "" and is_atom(strategy) and
             is_list(strategy_opts) and is_list(opts) do
    start_instance(
      name,
      [],
      Keyword.merge(opts, strategy: strategy, strategy_opts: strategy_opts, routes: [route])
    )
  end

  @doc """
  Start a switchboard instance from a JSON-safe configuration.

  The configuration is validated by `GenAgentServer.InstanceSpec` before
  anything starts and is fixed for the life of the instance. Returns the same
  description as `describe_instance/1`, or `{:error, :instance_exists}`,
  `{:error, {:invalid_instance_name, name}}`, `{:error, {:invalid_config,
  detail}}`, or `{:error, :instance_start_failed}`.
  """
  def create_instance(name, config) when is_binary(name) and is_map(config) do
    with {:ok, spec} <- GenAgentServer.InstanceSpec.parse(name, config),
         :ok <- ensure_absent(name) do
      opts = Keyword.put(spec.opts, :description, spec.description)

      case start_instance(name, spec.agents, opts) do
        {:ok, _pid} -> describe_instance(name)
        {:error, {:already_started, _pid}} -> {:error, :instance_exists}
        {:error, _reason} -> {:error, :instance_start_failed}
      end
    end
  end

  defp ensure_absent(name) do
    case Registry.lookup(GenAgentServer.Registry, {:instance, name}) do
      [] -> :ok
      _ -> {:error, :instance_exists}
    end
  end

  @doc """
  Routes, selected providers, models, efforts, and limits of an instance.

  Instances not started by `create_instance/2` report `configured: false` and
  route names only; their backend options are not exposed.
  """
  def describe_instance(name \\ session_name()) when is_binary(name) do
    GenAgentServer.Invocations.describe(name)
  end

  def stop_instance(name) when is_binary(name) do
    if name == session_name() do
      {:error, :default_instance}
    else
      case Registry.lookup(GenAgentServer.Registry, {:instance, name}) do
        [{pid, _}] -> DynamicSupervisor.terminate_child(GenAgentServer.InstanceSupervisor, pid)
        [] -> {:error, :not_found}
      end
    end
  end

  def agents(instance \\ session_name()) do
    GenAgentServer.Invocations.routes(instance)
  end

  def status(instance \\ session_name()) do
    case Registry.lookup(GenAgentServer.Registry, {:instance, instance}) do
      [{pid, _}] ->
        try do
          with {:ok, status} <- GenAgentEnsemble.status(instance),
               {:ok, routes} <- agents(instance) do
            {:ok, Map.put(status, :routes, routes)}
          end
        catch
          :exit, {:noproc, {GenServer, :call, _}} = reason ->
            if Process.alive?(pid), do: exit(reason), else: {:error, :instance_not_found}

          :exit, reason ->
            exit(reason)
        end

      [] ->
        {:error, :instance_not_found}
    end
  end

  def invoke(agent, prompt) when is_binary(agent) and is_binary(prompt) do
    invoke(session_name(), agent, prompt, [])
  end

  def invoke(instance, agent, prompt)
      when is_binary(instance) and is_binary(agent) and is_binary(prompt) do
    invoke(instance, agent, prompt, [])
  end

  @doc """
  Admit a turn with an optional `recipient: pid | nil` (default nil).
  The owner attempts one `{:gen_agent_server, :completion, metadata, result}`
  send per observed terminal result, before eviction. Metadata contains instance,
  agent, invocation_id, ensemble_token and source; cancellation adds cancellation_ack.
  Delivery is not durable and is not guaranteed after instance shutdown.
  Invalid recipients return `{:error, :invalid_recipient}` before admission.
  """
  def invoke(instance, agent, prompt, opts)
      when is_binary(instance) and is_binary(agent) and is_binary(prompt) and is_list(opts) do
    GenAgentServer.Invocations.invoke(instance, agent, prompt, opts)
  end

  def result(id) when is_binary(id), do: result(session_name(), id)

  def result(instance, id) when is_binary(instance) and is_binary(id) do
    GenAgentServer.Invocations.result(instance, id)
  end

  @doc """
  Cancel a pending invocation after collecting available completions.

  Returns `{:ok, :cancelled | :cancelled_unconfirmed}` if cancellation wins,
  or `{:error, :already_finished | :not_found | :instance_not_found | :unsupported}`.
  Unsupported cancellation leaves work pending. Retained cancellation results
  remain `{:ok, :failed, :cancelled}`; all retained terminal IDs are already finished.
  An external cancellation has notification acknowledgement `:cancelled_unconfirmed`.

  This synchronous call can block the invocation owner for potentially unbounded
  time. Acknowledgement does not guarantee external provider process settlement.
  Finalization releases raw admission capacity while unrelated work continues.
  """
  def cancel(instance, id) when is_binary(instance) and is_binary(id) do
    GenAgentServer.Invocations.cancel(instance, id)
  end

  def ask(agent, prompt, opts \\ []) when is_binary(agent) and is_binary(prompt) do
    ask_instance(session_name(), agent, prompt, opts)
  end

  def ask_instance(instance, agent, prompt, opts \\ [])
      when is_binary(instance) and is_binary(agent) and is_binary(prompt) and is_list(opts) do
    {timeout, route_opts} = Keyword.pop(opts, :timeout, :infinity)
    source = Keyword.get(route_opts, :source, :api)

    with {:ok, id} <- invoke(instance, agent, prompt, route_opts) do
      started_at_ms = System.monotonic_time(:millisecond)

      case await_result(instance, id, timeout) do
        {:error, :timeout} = error ->
          GenAgentServer.Telemetry.wait_timeout(
            instance,
            agent,
            id,
            source,
            started_at_ms
          )

          error

        result ->
          result
      end
    end
  end

  defp await_result(instance, id, timeout) do
    deadline =
      case timeout do
        :infinity -> :infinity
        ms when is_integer(ms) and ms >= 0 -> System.monotonic_time(:millisecond) + ms
      end

    await_until(instance, id, deadline)
  end

  defp await_until(instance, id, deadline) do
    case result(instance, id) do
      {:ok, :pending} ->
        now = System.monotonic_time(:millisecond)

        if deadline != :infinity and now >= deadline do
          {:error, :timeout}
        else
          Process.sleep(if(deadline == :infinity, do: 25, else: min(25, deadline - now)))
          await_until(instance, id, deadline)
        end

      {:ok, :completed, response} ->
        {:ok, response}

      {:ok, :failed, reason} ->
        {:error, reason}

      error ->
        error
    end
  end
end

defmodule GenAgentServer.Invocations do
  @moduledoc """
  Instance-local, bounded result store for asynchronous Ensemble turns.

  This process is the only consumer of its Ensemble session's `inbox/1`.
  Results are repeatable reads until evicted or the instance stops.
  IDs include a fresh random 192-bit instance-lifetime namespace. A restarted
  release or recreated instance cannot reuse an old VM-counter ID. Old IDs
  return `:not_found` when the instance exists, `:instance_not_found` otherwise.
  """

  use GenServer

  @sources [:api, :local_cli, :remote_cli, :scheduler, :mcp]

  @type result ::
          {:ok, :pending}
          | {:ok, :completed, GenAgent.Response.t()}
          | {:ok, :failed, term()}
          | {:error, :not_found | :instance_not_found}

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: via(name))
  end

  def invoke(name, agent, prompt, opts) do
    call_instance(name, {:invoke, agent, prompt, opts})
  end

  def routes(name), do: call_instance(name, :routes)

  def describe(name), do: call_instance(name, :describe)

  @spec result(String.t(), String.t()) :: result()
  def result(name, id), do: call_instance(name, {:result, id})

  def cancel(name, id), do: call_instance(name, {:cancel, id})

  def via(name), do: {:via, Registry, {GenAgentServer.Registry, {:invocations, name}}}

  defp call_instance(name, request) do
    case Registry.lookup(GenAgentServer.Registry, {:invocations, name}) do
      [{pid, _}] ->
        try do
          GenServer.call(pid, request, :infinity)
        catch
          :exit, reason ->
            if Process.alive?(pid), do: exit(reason), else: {:error, :instance_not_found}
        end

      [] ->
        {:error, :instance_not_found}
    end
  end

  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    configured_agents = opts |> Keyword.fetch!(:agents) |> Enum.map(&elem(&1, 0)) |> MapSet.new()
    routes = Keyword.fetch!(opts, :routes)
    strategy = Keyword.fetch!(opts, :strategy)
    max_in_flight = Keyword.fetch!(opts, :max_in_flight)
    max_results = Keyword.fetch!(opts, :max_results)
    poll_interval_ms = Keyword.fetch!(opts, :poll_interval_ms)

    if Enum.all?([max_in_flight, max_results, poll_interval_ms], &(is_integer(&1) and &1 > 0)) and
         routes != [] and Enum.all?(routes, &(is_binary(&1) and &1 != "")) and
         length(routes) == length(Enum.uniq(routes)) do
      case GenAgentEnsemble.status(name) do
        {:ok, %{agents: started, strategy: ^strategy}} ->
          if MapSet.size(configured_agents) == 0 or MapSet.new(started) == configured_agents do
            {:ok,
             %{
               name: name,
               id_namespace: Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false),
               agents: MapSet.new(routes),
               strategy: strategy,
               description: Keyword.get(opts, :description),
               pending: %{},
               by_token: %{},
               completed: %{},
               completion_order: :queue.new(),
               max_in_flight: max_in_flight,
               max_results: max_results,
               poll_interval_ms: poll_interval_ms,
               poll_scheduled?: false
             }}
          else
            {:stop, {:agent_start_failed, configured_agents, MapSet.new(started)}}
          end

        error ->
          {:stop, {:ensemble_unavailable, error}}
      end
    else
      {:stop, :invalid_invocation_limits}
    end
  end

  @impl true
  def handle_call(:routes, _from, state) do
    {:reply, {:ok, state.agents |> MapSet.to_list() |> Enum.sort()}, state}
  end

  @impl true
  def handle_call(:describe, _from, state) do
    routes = state.agents |> MapSet.to_list() |> Enum.sort()

    description =
      case state.description do
        %{configured: true} = configured ->
          configured

        _ ->
          %{configured: false, routes: Enum.map(routes, &%{name: &1})}
      end

    {:reply,
     {:ok,
      Map.merge(description, %{
        strategy: state.strategy,
        limits: %{max_in_flight: state.max_in_flight, max_results: state.max_results}
      })}, state}
  end

  def handle_call({:invoke, agent, prompt, opts}, _from, state) do
    case collect_available(state) do
      {:ok, state} -> admit(agent, prompt, opts, state)
      {:error, reason} -> {:stop, {:inbox_failed, reason}, {:error, reason}, state}
    end
  end

  def handle_call({:result, id}, _from, state) do
    case collect_available(state) do
      {:ok, state} ->
        result =
          cond do
            Map.has_key?(state.pending, id) -> {:ok, :pending}
            Map.has_key?(state.completed, id) -> Map.fetch!(state.completed, id)
            true -> {:error, :not_found}
          end

        {:reply, result, state}

      {:error, reason} ->
        {:stop, {:inbox_failed, reason}, {:error, reason}, state}
    end
  end

  def handle_call({:cancel, id}, _from, state) do
    case collect_available(state) do
      {:ok, state} -> cancel_pending(id, state)
      {:error, reason} -> {:stop, {:inbox_failed, reason}, {:error, reason}, state}
    end
  end

  defp cancel_pending(id, state) do
    cond do
      Map.has_key?(state.completed, id) ->
        {:reply, {:error, :already_finished}, state}

      not Map.has_key?(state.pending, id) ->
        {:reply, {:error, :not_found}, state}

      not (Code.ensure_loaded?(GenAgentEnsemble) and
               function_exported?(GenAgentEnsemble, :cancel, 2)) ->
        {:reply, {:error, :unsupported}, state}

      true ->
        token = state.pending[id].metadata.ensemble_token
        reply = apply(GenAgentEnsemble, :cancel, [state.name, token])

        state =
          case reply do
            {:ok, ack} when ack in [:cancelled, :cancelled_unconfirmed] ->
              put_in(state.pending[id].metadata[:cancellation_ack], ack)

            _ ->
              state
          end

        case collect_available(state) do
          {:ok, state} -> {:reply, reply, state}
          {:error, reason} -> {:stop, {:inbox_failed, reason}, {:error, reason}, state}
        end
    end
  end

  defp admit(agent, prompt, opts, state) do
    {source, route_opts} = Keyword.pop(opts, :source, :api)
    recipient = Keyword.get(opts, :recipient)
    recipient_ref = Keyword.get(opts, :recipient_ref)
    route_opts = Keyword.drop(route_opts, [:recipient, :recipient_ref])

    cond do
      not Enum.all?(Keyword.get_values(opts, :recipient_ref), &(is_nil(&1) or is_reference(&1))) ->
        reject(
          state,
          agent,
          if(source in @sources, do: source, else: :unknown),
          :invalid_recipient_ref
        )

      not Enum.all?(Keyword.get_values(opts, :recipient), &(is_nil(&1) or is_pid(&1))) ->
        reject(
          state,
          agent,
          if(source in @sources, do: source, else: :unknown),
          :invalid_recipient
        )

      source not in @sources ->
        reject(state, agent, :unknown, :invalid_source)

      not MapSet.member?(state.agents, agent) ->
        reject(state, agent, source, {:unknown_agent, agent})

      map_size(state.pending) >= state.max_in_flight ->
        reject(state, agent, source, :busy)

      true ->
        ensemble_opts =
          if state.strategy == GenAgentEnsemble.Strategies.Switchboard,
            do: Keyword.put(route_opts, :agent, agent),
            else: route_opts

        case GenAgentEnsemble.tell(state.name, prompt, ensemble_opts) do
          {:ok, token} ->
            id =
              "inv-" <>
                state.id_namespace <>
                "-" <>
                Integer.to_string(System.unique_integer([:positive, :monotonic]))

            started_at_ms = System.monotonic_time(:millisecond)

            metadata = %{
              instance: state.name,
              agent: agent,
              invocation_id: id,
              ensemble_token: token,
              source: source
            }

            metadata =
              if is_reference(recipient_ref),
                do: Map.put(metadata, :recipient_ref, recipient_ref),
                else: metadata

            state = %{
              state
              | pending:
                  Map.put(state.pending, id, %{
                    metadata: metadata,
                    started_at_ms: started_at_ms,
                    recipient: recipient
                  }),
                by_token: Map.put(state.by_token, token, id)
            }

            GenAgentServer.Telemetry.start(metadata)
            {:reply, {:ok, id}, schedule_poll(state)}

          {:error, reason} ->
            reject(state, agent, source, reason)
        end
    end
  end

  defp reject(state, agent, source, reason) do
    GenAgentServer.Telemetry.rejected(state.name, agent, source, reason)
    {:reply, {:error, reason}, state}
  end

  @impl true
  def handle_info(:collect, state) do
    state = %{state | poll_scheduled?: false}

    case collect_available(state) do
      {:ok, state} ->
        {:noreply, schedule_poll(state)}

      {:error, reason} ->
        {:stop, {:inbox_failed, reason}, state}
    end
  end

  defp collect_available(%{pending: pending} = state) when map_size(pending) == 0,
    do: {:ok, state}

  defp collect_available(state) do
    case GenAgentEnsemble.inbox(state.name) do
      {:ok, entries} when is_list(entries) ->
        {:ok, Enum.reduce(entries, state, &record_completion/2)}

      other ->
        {:error, other}
    end
  end

  defp record_completion({token, outcome}, state) do
    case Map.pop(state.by_token, token) do
      {nil, _} ->
        state

      {id, by_token} ->
        %{metadata: metadata, started_at_ms: started_at_ms, recipient: recipient} =
          Map.fetch!(state.pending, id)

        metadata =
          if outcome == {:error, :cancelled},
            do: Map.put_new(metadata, :cancellation_ack, :cancelled_unconfirmed),
            else: metadata

        result =
          case outcome do
            {:ok, response} ->
              GenAgentServer.Telemetry.stop(metadata, started_at_ms)
              {:ok, :completed, response}

            {:error, reason} ->
              GenAgentServer.Telemetry.error(metadata, started_at_ms, reason)
              {:ok, :failed, reason}
          end

        state = %{
          state
          | by_token: by_token,
            pending: Map.delete(state.pending, id),
            completed: Map.put(state.completed, id, result),
            completion_order: :queue.in(id, state.completion_order)
        }

        if is_pid(recipient),
          do: send(recipient, {:gen_agent_server, :completion, metadata, result})

        evict_excess(state)
    end
  end

  defp evict_excess(state) do
    if map_size(state.completed) > state.max_results do
      {{:value, oldest}, order} = :queue.out(state.completion_order)
      %{state | completed: Map.delete(state.completed, oldest), completion_order: order}
    else
      state
    end
  end

  defp schedule_poll(%{poll_scheduled?: true} = state), do: state
  defp schedule_poll(%{pending: pending} = state) when map_size(pending) == 0, do: state

  defp schedule_poll(state) do
    Process.send_after(self(), :collect, state.poll_interval_ms)
    %{state | poll_scheduled?: true}
  end
end

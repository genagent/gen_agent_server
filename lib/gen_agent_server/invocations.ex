defmodule GenAgentServer.Invocations do
  @moduledoc """
  Instance-local, bounded result store for asynchronous Ensemble turns.

  This process is the only consumer of its Ensemble session's `inbox/1`.
  Results are repeatable reads until evicted or the instance stops.
  """

  use GenServer

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

  @spec result(String.t(), String.t()) :: result()
  def result(name, id), do: call_instance(name, {:result, id})

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
    max_in_flight = Keyword.fetch!(opts, :max_in_flight)
    max_results = Keyword.fetch!(opts, :max_results)
    poll_interval_ms = Keyword.fetch!(opts, :poll_interval_ms)

    if Enum.all?([max_in_flight, max_results, poll_interval_ms], &(is_integer(&1) and &1 > 0)) do
      case GenAgentEnsemble.status(name) do
        {:ok, %{agents: started}} ->
          if MapSet.new(started) == configured_agents do
            {:ok,
             %{
               name: name,
               agents: configured_agents,
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

  defp admit(agent, prompt, opts, state) do
    cond do
      not MapSet.member?(state.agents, agent) ->
        {:reply, {:error, {:unknown_agent, agent}}, state}

      map_size(state.pending) >= state.max_in_flight ->
        {:reply, {:error, :busy}, state}

      true ->
        case GenAgentEnsemble.tell(state.name, prompt, Keyword.put(opts, :agent, agent)) do
          {:ok, token} ->
            id = "inv-" <> Integer.to_string(System.unique_integer([:positive, :monotonic]))

            state = %{
              state
              | pending: Map.put(state.pending, id, token),
                by_token: Map.put(state.by_token, token, id)
            }

            {:reply, {:ok, id}, schedule_poll(state)}

          error ->
            {:reply, error, state}
        end
    end
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
        result =
          case outcome do
            {:ok, response} -> {:ok, :completed, response}
            {:error, reason} -> {:ok, :failed, reason}
          end

        state = %{
          state
          | by_token: by_token,
            pending: Map.delete(state.pending, id),
            completed: Map.put(state.completed, id, result),
            completion_order: :queue.in(id, state.completion_order)
        }

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

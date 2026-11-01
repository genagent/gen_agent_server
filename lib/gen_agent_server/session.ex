defmodule GenAgentServer.Session do
  @moduledoc """
  One agent session driven directly through a CLI wrapper.

  Spike for the `agent` operation (genagent/gen_agent_server#140). A session
  is one process holding a wrapper session struct (`ClaudeWrapper.Session` or
  `CodexWrapper.Session`), which carries the provider's resume id between
  turns. No GenAgent server, Ensemble session or backend adapter is involved.

  Turns run one at a time in a `GenAgentServer.SessionTasks` child. A prompt
  submitted during a turn queues behind it. Each turn gets an invocation id
  and a held result; callers can wait for it. There is no turn limit.

  Cancelling kills the turn task. The wrapper runner owns the CLI
  subprocess, so cancellation does not prove the provider process exited.
  """

  use GenServer

  @max_results 100
  @max_wait_ms 600_000

  @type result ::
          %{status: :pending}
          | %{status: :completed, text: String.t(), usage: map() | nil}
          | %{status: :failed, error: term()}
          | %{status: :cancelled}

  # -- client ------------------------------------------------------------------

  @doc """
  Start a session.

  Options: `:id` (required), `:provider` (`"claude"` or `"codex"`), `:cwd`
  (required), and optionally `:model`, `:effort` and `:access`.
  """
  def start(opts) do
    id = Keyword.fetch!(opts, :id)

    with {:ok, adapter, wrapper_session} <- build(opts) do
      spec = %{
        id: {__MODULE__, id},
        start:
          {GenServer, :start_link,
           [
             __MODULE__,
             %{id: id, opts: opts, adapter: adapter, session: wrapper_session},
             [name: via(id)]
           ]},
        restart: :temporary
      }

      case DynamicSupervisor.start_child(GenAgentServer.SessionSupervisor, spec) do
        {:ok, _pid} -> {:ok, id}
        {:error, {:already_started, _}} -> {:error, :session_exists}
        error -> error
      end
    end
  end

  @doc "Queue a prompt. Returns its invocation id."
  def submit(id, prompt), do: call(id, {:submit, prompt})

  @doc "The invocation's result, waiting up to `wait_ms` for a terminal one."
  def result(id, invocation_id \\ nil, wait_ms \\ 0) do
    wait_ms = min(wait_ms, @max_wait_ms)
    call(id, {:result, invocation_id, wait_ms}, wait_ms + 5_000)
  end

  @doc "Cancel the running turn and drop queued prompts."
  def cancel(id), do: call(id, :cancel)

  @doc "Stop the session. Its results are discarded."
  def stop(id) do
    case GenServer.whereis(via(id)) do
      nil -> {:error, :session_not_found}
      pid -> DynamicSupervisor.terminate_child(GenAgentServer.SessionSupervisor, pid)
    end
  end

  @doc "Describe the session: provider, cwd, provider session id, turn counts."
  def describe(id), do: call(id, :describe)

  @doc "Ids of running sessions, sorted."
  def list do
    GenAgentServer.Registry
    |> Registry.select([{{{:session, :"$1"}, :_, :_}, [], [:"$1"]}])
    |> Enum.sort()
  end

  def via(id), do: {:via, Registry, {GenAgentServer.Registry, {:session, id}}}

  defp call(id, message, timeout \\ 5_000) do
    GenServer.call(via(id), message, timeout)
  catch
    :exit, {:noproc, _} -> {:error, :session_not_found}
    :exit, {{:shutdown, _}, _} -> {:error, :session_not_found}
  end

  defp build(opts) do
    adapter =
      case Keyword.get(opts, :provider, "codex") do
        "claude" -> {:ok, GenAgentServer.Session.Claude}
        "codex" -> {:ok, GenAgentServer.Session.Codex}
        other -> {:error, {:unknown_provider, other}}
      end

    with {:ok, adapter} <- adapter,
         {:ok, wrapper_session} <- adapter.new(opts),
         do: {:ok, adapter, wrapper_session}
  end

  # -- server ------------------------------------------------------------------

  @impl true
  def init(init) do
    {:ok,
     Map.merge(init, %{
       next: 1,
       current: nil,
       queue: :queue.new(),
       results: %{},
       order: :queue.new(),
       waiters: %{},
       latest: nil,
       completed: 0,
       failed: 0
     })}
  end

  @impl true
  def handle_call({:submit, prompt}, _from, state) do
    invocation_id = "#{state.id}/#{state.next}"

    state =
      %{state | next: state.next + 1, latest: invocation_id}
      |> put_result(invocation_id, %{status: :pending})
      |> Map.update!(:queue, &:queue.in({invocation_id, prompt}, &1))
      |> maybe_start_turn()

    {:reply, {:ok, invocation_id}, state}
  end

  def handle_call({:result, nil, _wait_ms}, _from, %{latest: nil} = state),
    do: {:reply, {:error, :no_invocations}, state}

  def handle_call({:result, nil, wait_ms}, from, state),
    do: handle_call({:result, state.latest, wait_ms}, from, state)

  def handle_call({:result, invocation_id, wait_ms}, from, state) do
    case Map.fetch(state.results, invocation_id) do
      :error ->
        {:reply, {:error, :invocation_not_found}, state}

      {:ok, %{status: :pending}} when wait_ms > 0 ->
        timer = Process.send_after(self(), {:wait_expired, invocation_id, from}, wait_ms)
        waiters = Map.update(state.waiters, invocation_id, [{from, timer}], &[{from, timer} | &1])
        {:noreply, %{state | waiters: waiters}}

      {:ok, result} ->
        {:reply, {:ok, Map.put(result, :invocation_id, invocation_id)}, state}
    end
  end

  def handle_call(:cancel, _from, state) do
    cancelled =
      Enum.map(:queue.to_list(state.queue), &elem(&1, 0)) ++
        if(state.current, do: [state.current.invocation_id], else: [])

    if state.current do
      Process.demonitor(state.current.task.ref, [:flush])
      Task.Supervisor.terminate_child(GenAgentServer.SessionTasks, state.current.task.pid)
    end

    state =
      Enum.reduce(cancelled, %{state | current: nil, queue: :queue.new()}, fn id, acc ->
        finish(acc, id, %{status: :cancelled})
      end)

    {:reply, {:ok, cancelled}, state}
  end

  def handle_call(:describe, _from, state) do
    {:reply,
     {:ok,
      %{
        session_id: state.id,
        provider: Keyword.get(state.opts, :provider, "codex"),
        cwd: Keyword.get(state.opts, :cwd),
        model: Keyword.get(state.opts, :model),
        effort: Keyword.get(state.opts, :effort),
        access: Keyword.get(state.opts, :access) || "inherit",
        provider_session_id: state.adapter.session_id(state.session),
        running: state.current && state.current.invocation_id,
        queued: :queue.len(state.queue),
        completed: state.completed,
        failed: state.failed,
        latest: state.latest
      }}, state}
  end

  @impl true
  def handle_info({ref, outcome}, %{current: %{task: %{ref: ref}} = current} = state) do
    Process.demonitor(ref, [:flush])

    {state, result} =
      case outcome do
        {:ok, session, response} ->
          {%{state | session: session, completed: state.completed + 1},
           Map.merge(%{status: :completed}, response)}

        {:error, reason} ->
          {%{state | failed: state.failed + 1}, %{status: :failed, error: reason}}
      end

    result = Map.put(result, :duration_ms, elapsed_ms(current.started))

    state
    |> Map.put(:current, nil)
    |> finish(current.invocation_id, result)
    |> maybe_start_turn()
    |> then(&{:noreply, &1})
  end

  def handle_info(
        {:DOWN, ref, :process, _pid, reason},
        %{current: %{task: %{ref: ref}} = current} = state
      ) do
    state
    |> Map.merge(%{current: nil, failed: state.failed + 1})
    |> finish(current.invocation_id, %{status: :failed, error: {:turn_crashed, reason}})
    |> maybe_start_turn()
    |> then(&{:noreply, &1})
  end

  def handle_info({:wait_expired, invocation_id, from}, state) do
    case Map.get(state.waiters, invocation_id, []) do
      [] ->
        {:noreply, state}

      waiters ->
        {expired, rest} = Enum.split_with(waiters, fn {f, _} -> f == from end)

        if expired != [] do
          GenServer.reply(from, {:ok, %{status: :pending, invocation_id: invocation_id}})
        end

        {:noreply, %{state | waiters: Map.put(state.waiters, invocation_id, rest)}}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp maybe_start_turn(%{current: nil} = state) do
    case :queue.out(state.queue) do
      {:empty, _} ->
        state

      {{:value, {invocation_id, prompt}}, queue} ->
        adapter = state.adapter
        session = state.session

        task =
          Task.Supervisor.async_nolink(GenAgentServer.SessionTasks, fn ->
            adapter.run(session, prompt)
          end)

        %{
          state
          | queue: queue,
            current: %{
              invocation_id: invocation_id,
              task: task,
              started: System.monotonic_time()
            }
        }
    end
  end

  defp maybe_start_turn(state), do: state

  defp finish(state, invocation_id, result) do
    {waiters, all} = Map.pop(state.waiters, invocation_id, [])

    for {from, timer} <- waiters do
      Process.cancel_timer(timer)
      GenServer.reply(from, {:ok, Map.put(result, :invocation_id, invocation_id)})
    end

    %{state | waiters: all, results: Map.put(state.results, invocation_id, result)}
  end

  defp put_result(state, invocation_id, result) do
    order = :queue.in(invocation_id, state.order)
    results = Map.put(state.results, invocation_id, result)

    if :queue.len(order) > @max_results do
      {{:value, oldest}, order} = :queue.out(order)
      %{state | order: order, results: Map.delete(results, oldest)}
    else
      %{state | order: order, results: results}
    end
  end

  defp elapsed_ms(started),
    do: System.convert_time_unit(System.monotonic_time() - started, :native, :millisecond)
end

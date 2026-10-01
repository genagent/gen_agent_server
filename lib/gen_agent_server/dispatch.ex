defmodule GenAgentServer.Dispatch do
  @moduledoc """
  Submits configured calendar jobs through the same bounded invocation API as
  manual requests. The Quantum task stays alive until the turn is terminal, so
  non-overlap applies to the agent turn rather than only its submission.
  """

  use GenServer

  def start_link(jobs), do: GenServer.start_link(__MODULE__, jobs, name: __MODULE__)

  def jobs, do: GenServer.call(__MODULE__, :jobs)
  def latest(name) when is_binary(name), do: GenServer.call(__MODULE__, {:latest, name})

  def run_job(name) when is_binary(name) do
    case GenServer.call(__MODULE__, {:claim, name}) do
      {:ok, job, ref} ->
        try do
          run_claimed(job, ref)
        after
          GenServer.call(__MODULE__, {:release, ref})
        end

      error ->
        error
    end
  end

  defp run_claimed(job, ref) do
    prompt =
      case job.prompt_source do
        {:literal, text} -> {:ok, text}
        {:file, path} -> File.read(path)
      end

    with {:ok, text} <- prompt,
         {:ok, id} <- GenAgentServer.invoke(job.instance, job.agent, text, source: :scheduler) do
      GenServer.call(__MODULE__, {:record, ref, id})
      wait(job.instance, id)
    else
      error ->
        GenServer.call(__MODULE__, {:rejected, ref})
        error
    end
  end

  defp wait(instance, id) do
    case GenAgentServer.result(instance, id) do
      {:ok, :pending} ->
        Process.sleep(100)
        wait(instance, id)

      {:ok, :completed, _response} ->
        :ok

      {:ok, :failed, _reason} ->
        {:error, :turn_failed}

      error ->
        error
    end
  end

  @impl true
  def init(jobs) do
    {:ok, %{jobs: Map.new(jobs, &{&1.name, &1}), active: %{}, latest: %{}}}
  end

  @impl true
  def handle_call(:jobs, _from, state) do
    {:reply, state.jobs |> Map.keys() |> Enum.sort(), state}
  end

  def handle_call({:latest, name}, _from, state) do
    reply =
      case Map.fetch(state.jobs, name) do
        :error -> {:error, :unknown_job}
        {:ok, _job} -> {:ok, Map.get(state.latest, name)}
      end

    {:reply, reply, state}
  end

  def handle_call({:claim, name}, {pid, _tag}, state) do
    case Map.fetch(state.jobs, name) do
      :error ->
        {:reply, {:error, :unknown_job}, state}

      {:ok, job} ->
        busy? = Enum.any?(state.active, fn {_ref, active_name} -> active_name == name end)

        if busy? and not job.overlap do
          {:reply, {:error, :overlap}, state}
        else
          ref = Process.monitor(pid)
          {:reply, {:ok, job, ref}, %{state | active: Map.put(state.active, ref, name)}}
        end
    end
  end

  def handle_call({:record, ref, id}, _from, state) do
    name = Map.fetch!(state.active, ref)
    {:reply, :ok, %{state | latest: Map.put(state.latest, name, id)}}
  end

  def handle_call({:rejected, _ref}, _from, state), do: {:reply, :ok, state}

  def handle_call({:release, ref}, _from, state) do
    Process.demonitor(ref, [:flush])
    {:reply, :ok, %{state | active: Map.delete(state.active, ref)}}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    {:noreply, %{state | active: Map.delete(state.active, ref)}}
  end
end

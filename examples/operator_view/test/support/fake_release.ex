defmodule OperatorView.FakeRelease do
  @moduledoc false
  # Scripted stand-in for a running release, used as the observer transport.
  # Every operation is reported to the owning test process. In :gate mode a
  # call waits until release/0, so a test decides when a refresh worker gets
  # its reply. {:error, code} mode answers every call with that Ops error code.

  @behaviour OperatorView.Transport
  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl OperatorView.Transport
  def call(operation, args, _timeout_ms) do
    GenServer.call(__MODULE__, {:call, operation, args}, :infinity)
  end

  def update(fun), do: GenServer.call(__MODULE__, {:update, fun})
  def release, do: GenServer.call(__MODULE__, :release)
  def gated, do: GenServer.call(__MODULE__, :gated)
  def waiting_pids, do: GenServer.call(__MODULE__, :waiting_pids)

  @impl GenServer
  def init(opts) do
    state = %{
      owner: Keyword.fetch!(opts, :owner),
      instances: Keyword.get(opts, :instances, []),
      data: Keyword.get(opts, :data, %{}),
      mode: :reply,
      waiting: []
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:call, operation, args}, from, state) do
    send(state.owner, {:release_call, operation, args})

    case state.mode do
      :gate -> {:noreply, %{state | waiting: state.waiting ++ [{from, operation, args}]}}
      {:error, code} -> {:reply, failure(code), state}
      :reply -> {:reply, answer(operation, args, state), state}
    end
  end

  def handle_call({:update, fun}, _from, state), do: {:reply, :ok, fun.(state)}
  def handle_call(:gated, _from, state), do: {:reply, length(state.waiting), state}

  def handle_call(:waiting_pids, _from, state) do
    {:reply, Enum.map(state.waiting, fn {{pid, _tag}, _operation, _args} -> pid end), state}
  end

  def handle_call(:release, _from, state) do
    for {from, operation, args} <- state.waiting do
      GenServer.reply(from, answer(operation, args, state))
    end

    {:reply, :ok, %{state | waiting: []}}
  end

  defp answer("instances", _args, state), do: {:ok, %{"instances" => state.instances}}

  defp answer(operation, %{"instance" => instance}, state) do
    if instance in state.instances and Map.has_key?(state.data, instance) do
      {:ok, Map.fetch!(state.data[instance], operation)}
    else
      failure("instance_not_found")
    end
  end

  # The message imitates release output that must never reach the page.
  defp failure(code) do
    {:error, %{"code" => code, "message" => "/private/release/bin/gen_agent_server #{code}"}}
  end
end

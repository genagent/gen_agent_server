defmodule GenAgentServer.Instance do
  @moduledoc """
  Owns one Ensemble session and its repeatable invocation results.

  An instance is a supervision boundary. If either child fails, the instance
  stops instead of restarting with an empty session or result store.
  """

  use Supervisor

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    Supervisor.start_link(__MODULE__, opts, name: via(name))
  end

  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    agents = Keyword.fetch!(opts, :agents)

    children = [
      {GenAgentEnsemble.Server,
       name: name, strategy: GenAgentEnsemble.Strategies.Switchboard, opts: [agents: agents]},
      {GenAgentServer.Invocations,
       name: name,
       agents: agents,
       max_in_flight: Keyword.get(opts, :max_in_flight, 16),
       max_results: Keyword.get(opts, :max_results, 100),
       poll_interval_ms: Keyword.get(opts, :poll_interval_ms, 100)}
    ]

    Supervisor.init(children, strategy: :one_for_all, max_restarts: 0)
  end

  def via(name), do: {:via, Registry, {GenAgentServer.Registry, {:instance, name}}}

  def child_spec(opts) do
    %{
      id: {__MODULE__, Keyword.fetch!(opts, :name)},
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary,
      type: :supervisor
    }
  end
end

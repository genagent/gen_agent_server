defmodule GenAgentServer.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    session_name = Application.fetch_env!(:gen_agent_server, :session_name)
    agents = Application.fetch_env!(:gen_agent_server, :agents)

    children = [
      {GenAgentEnsemble.Server,
       name: session_name,
       strategy: GenAgentEnsemble.Strategies.Switchboard,
       opts: [agents: agents]}
    ]

    Supervisor.start_link(children,
      strategy: :one_for_one,
      max_restarts: 0,
      name: GenAgentServer.Supervisor
    )
  end
end

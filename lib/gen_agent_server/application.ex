defmodule GenAgentServer.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    session_name = Application.fetch_env!(:gen_agent_server, :session_name)
    agents = Application.fetch_env!(:gen_agent_server, :agents)

    children = [
      {Registry, keys: :unique, name: GenAgentServer.Registry},
      {DynamicSupervisor, strategy: :one_for_one, name: GenAgentServer.InstanceSupervisor},
      Supervisor.child_spec(
        {GenAgentServer.Instance, name: session_name, agents: agents},
        id: :default_instance,
        restart: :permanent
      )
    ]

    Supervisor.start_link(children,
      strategy: :rest_for_one,
      max_restarts: 0,
      name: GenAgentServer.Supervisor
    )
  end
end

defmodule GenAgentServer.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    session_name = Application.fetch_env!(:gen_agent_server, :session_name)
    agents = Application.fetch_env!(:gen_agent_server, :agents)
    profile_file = Application.get_env(:gen_agent_server, :profile_file)
    profiles = if profile_file, do: GenAgentServer.Profiles.load!(profile_file), else: []

    if Enum.any?(profiles, fn {name, _agents} -> name == session_name end) do
      raise ArgumentError, "profile name conflicts with the default instance: #{session_name}"
    end

    children =
      [
        {Registry, keys: :unique, name: GenAgentServer.Registry},
        {DynamicSupervisor, strategy: :one_for_one, name: GenAgentServer.InstanceSupervisor},
        Supervisor.child_spec(
          {GenAgentServer.Instance, name: session_name, agents: agents},
          id: :default_instance,
          restart: :permanent
        )
      ] ++
        Enum.map(profiles, fn {name, profile_agents} ->
          Supervisor.child_spec(
            {GenAgentServer.Instance, name: name, agents: profile_agents},
            id: {:profile, name},
            restart: :permanent
          )
        end)

    Supervisor.start_link(children,
      strategy: :rest_for_one,
      max_restarts: 0,
      name: GenAgentServer.Supervisor
    )
  end
end

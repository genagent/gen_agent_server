defmodule GenAgentServer.MixProject do
  use Mix.Project

  def project do
    [
      app: :gen_agent_server,
      version: "0.6.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {GenAgentServer.Application, []},
      # Defaults for use as a dependency; config/runtime.exs overrides them here.
      env: [
        session_name: "server/default",
        agents: [
          {"echo", GenAgentEnsemble.Agents.Simple, [backend: GenAgentEnsemble.Backends.Echo]}
        ],
        extensions: []
      ]
    ]
  end

  defp deps do
    [
      {:gen_agent, "~> 0.11.0"},
      {:gen_agent_ensemble, "~> 0.8.0"},
      {:gen_agent_claude, "~> 0.4.0"},
      {:gen_agent_codex, "~> 0.7.0"},
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.0"}
    ]
  end
end

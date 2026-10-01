defmodule GenAgentServer.MixProject do
  use Mix.Project

  def project do
    [
      app: :gen_agent_server,
      version: "0.1.0-dev",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger], mod: {GenAgentServer.Application, []}]
  end

  defp deps do
    [
      {:gen_agent, "~> 0.5.0"},
      {:gen_agent_ensemble, "~> 0.2.1"},
      {:gen_agent_claude, "~> 0.1.5"},
      {:gen_agent_codex, "~> 0.2.5"},
      {:jason, "~> 1.4"},
      {:quantum, "~> 3.5"},
      {:telemetry, "~> 1.0"}
    ]
  end
end

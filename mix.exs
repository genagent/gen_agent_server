defmodule GenAgentServer.MixProject do
  use Mix.Project

  def project do
    [
      app: :gen_agent_server,
      version: "0.4.0",
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
      {:gen_agent, "~> 0.6.1 or ~> 0.7.0"},
      {:gen_agent_ensemble, "~> 0.4.0 or ~> 0.5.0 or ~> 0.6.0"},
      {:gen_agent_claude, "~> 0.2.0"},
      {:gen_agent_codex, "~> 0.4.0"},
      {:jason, "~> 1.4"},
      {:quantum, "~> 3.5"},
      {:snodo, "~> 0.4.1"},
      {:telemetry, "~> 1.0"}
    ]
  end
end

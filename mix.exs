defmodule GenAgentServer.MixProject do
  use Mix.Project

  def project do
    [
      app: :gen_agent_server,
      version: "0.4.1",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger, :crypto], mod: {GenAgentServer.Application, []}]
  end

  defp deps do
    [
      # Temporary immutable source pins until the response_text adapter option is released.
      {:gen_agent,
       github: "genagent/gen_agent",
       ref: "b251a1321242edea1c895f76e0a16d38c357dc53",
       override: true},
      {:gen_agent_ensemble, "~> 0.4.0 or ~> 0.5.0 or ~> 0.6.0"},
      {:gen_agent_claude, "~> 0.2.5"},
      {:gen_agent_codex,
       github: "genagent/gen_agent",
       ref: "b251a1321242edea1c895f76e0a16d38c357dc53",
       sparse: "integrations/codex"},
      {:jason, "~> 1.4"},
      {:quantum, "~> 3.5"},
      {:snodo, "~> 0.4.1"},
      {:telemetry, "~> 1.0"}
    ]
  end
end

defmodule ForcolaPublishedAdaptersProbe.MixProject do
  use Mix.Project

  def project do
    [app: :forcola_published_adapters_probe, version: "0.1.0", elixir: "~> 1.19", deps: deps()]
  end

  def application, do: [extra_applications: [:logger]]

  defp deps do
    [
      {:gen_agent_codex, "~> 0.4.3"},
      {:gen_agent_claude, "~> 0.2.2"},
      {:forcola, "~> 0.4.0"}
    ]
  end
end

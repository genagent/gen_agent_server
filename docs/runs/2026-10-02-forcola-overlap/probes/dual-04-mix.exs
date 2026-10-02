defmodule ForcolaDualProbe.MixProject do
  use Mix.Project

  def project do
    [app: :forcola_dual_probe, version: "0.1.0", elixir: "~> 1.19", deps: deps()]
  end

  def application, do: [extra_applications: [:logger]]

  defp deps do
    [
      {:codex_wrapper, path: "/tmp/codex_wrapper_forcola_196"},
      {:claude_wrapper, "~> 0.14.5"},
      {:forcola, "~> 0.4.0"}
    ]
  end
end

defmodule OperatorView.MixProject do
  use Mix.Project

  # Fetched dependencies and build output live under the server's ignored
  # `_build`, so the server's `examples/**/*.{ex,exs}` formatter inputs never
  # reach dependency sources.
  @artifacts "../../_build/operator_view"

  def project do
    [
      app: :operator_view,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      build_path: Path.join(@artifacts, "build"),
      deps_path: Path.join(@artifacts, "deps"),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [mod: {OperatorView.Application, []}, extra_applications: [:logger, :crypto]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      # Only the server's existing Ops.Remote reader is used. runtime: false keeps
      # the server application, its instances and its listeners out of this VM.
      {:gen_agent_server, path: "../..", runtime: false},
      {:phoenix, "~> 1.8"},
      {:phoenix_html, "~> 4.2"},
      {:phoenix_live_view, "~> 1.1"},
      {:bandit, "~> 1.6"},
      {:jason, "~> 1.4"},
      {:lazy_html, ">= 0.1.0", only: :test}
    ]
  end
end

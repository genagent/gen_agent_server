defmodule GenAgentServerMCP.MixProject do
  use Mix.Project

  def project do
    [
      app: :gen_agent_server_mcp,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application, do: [extra_applications: [:logger, :crypto]]

  defp deps do
    [
      {:gen_agent_server, path: "../.."},
      {:snodo, "~> 0.4.1"},
      {:jason, "~> 1.4"},
      # Test-only, so the tests cover tools for other extensions' operations.
      {:gen_agent_server_public_source, path: "../public_source", only: :test}
    ]
  end
end

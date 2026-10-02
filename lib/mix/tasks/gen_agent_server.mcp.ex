defmodule Mix.Tasks.GenAgentServer.Mcp do
  @moduledoc """
  Serve the GenAgent Server MCP tools over stdio.

      MIX_QUIET=1 mix gen_agent_server.mcp

  After the server starts, stdout carries only
  MCP protocol messages; Logger output goes to stderr. The task starts its own
  application, so instances and results last for the MCP session. See
  `GenAgentServer.MCP` for the tool catalogue.
  """
  @shortdoc "Serve GenAgent Server MCP tools over stdio"
  use Mix.Task

  @impl true
  def run(_args) do
    Mix.shell(Mix.Shell.Quiet)
    # Compiles and loads config/runtime.exs without starting the application.
    Mix.Task.run("app.config")
    GenAgentServer.MCP.serve()
  end
end

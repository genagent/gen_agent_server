defmodule GenAgentServer.MCP.Server do
  @moduledoc false

  # Fixed at compile time so releases, which do not ship Mix, advertise it too.
  @version Mix.Project.config()[:version]

  use Snodo.Server,
    name: "gen-agent-server",
    version: @version,
    protocols: [
      Snodo.Protocol.V2026_07_28,
      Snodo.Protocol.V2025_11_25,
      Snodo.Protocol.V2025_06_18
    ]

  tool(GenAgentServer.MCP.Tools.Instances)
  tool(GenAgentServer.MCP.Tools.Agents)
  tool(GenAgentServer.MCP.Tools.Status)
  tool(GenAgentServer.MCP.Tools.Invoke)
  tool(GenAgentServer.MCP.Tools.Result)
  tool(GenAgentServer.MCP.Tools.Ask)
end

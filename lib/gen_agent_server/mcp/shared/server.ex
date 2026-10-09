defmodule GenAgentServer.MCP.Shared.Server do
  @moduledoc false
  @version Mix.Project.config()[:version]
  use Snodo.Server,
    name: "gen-agent-server-shared",
    version: @version,
    instructions:
      "Shared server: call instances, then supply an explicit allowed instance to every tool. " <>
        "Use invoke then result for long turns. ask waits at most 5000 ms and returns an ID. " <>
        "Results are shared, repeatable until evicted, and volatile across release restart. " <>
        "A disconnect stops waiting but does not cancel admitted provider work. Do not retry submission blindly.",
    protocols: [
      Snodo.Protocol.V2026_07_28,
      Snodo.Protocol.V2025_11_25,
      Snodo.Protocol.V2025_06_18
    ]

  tool(GenAgentServer.MCP.Shared.Tools.Instances)
  tool(GenAgentServer.MCP.Shared.Tools.Agents)
  tool(GenAgentServer.MCP.Shared.Tools.Status)
  tool(GenAgentServer.MCP.Shared.Tools.DescribeInstance)
  tool(GenAgentServer.MCP.Shared.Tools.Invoke)
  tool(GenAgentServer.MCP.Shared.Tools.Result)
  tool(GenAgentServer.MCP.Shared.Tools.Ask)
end

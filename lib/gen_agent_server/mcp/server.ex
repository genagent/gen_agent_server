defmodule GenAgentServer.MCP.Server do
  @moduledoc false

  # Fixed at compile time so releases, which do not ship Mix, advertise it too.
  @version Mix.Project.config()[:version]

  use Snodo.Server,
    name: "gen-agent-server",
    version: @version,
    instructions:
      "GenAgent Server runs Claude, Codex, and Echo routes in named instances. " <>
        "Read gen-agent://guide/index for focused operating guides. " <>
        "Use instances and describe_instance to inspect state; create_instance to select " <>
        "providers, models, and project directories; invoke then result for long turns. " <>
        "Instances and results belong to this MCP process and disappear when it exits.",
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
  tool(GenAgentServer.MCP.Tools.CreateInstance)
  tool(GenAgentServer.MCP.Tools.DescribeInstance)
  tool(GenAgentServer.MCP.Tools.StopInstance)

  resource(GenAgentServer.MCP.Resources.Index)
  resource(GenAgentServer.MCP.Resources.Quickstart)
  resource(GenAgentServer.MCP.Resources.Invocations)
  resource(GenAgentServer.MCP.Resources.Scope)
  resource(GenAgentServer.MCP.Resources.Capabilities)
end

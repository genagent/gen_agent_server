import Config

config :gen_agent_server, GenAgentServer.RuntimeConfig.from_env!()
config :gen_agent_server, :shared_mcp, GenAgentServer.MCP.Shared.Config.from_release_env!()

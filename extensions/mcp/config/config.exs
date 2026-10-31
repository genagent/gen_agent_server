import Config

config :gen_agent_server, extensions: [GenAgentServer.MCP]

if config_env() == :test do
  config :gen_agent_server, extensions: [GenAgentServer.MCP, GenAgentServer.PublicSource]
end

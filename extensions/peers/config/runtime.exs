import Config

config :gen_agent_server, GenAgentServer.RuntimeConfig.from_env!()

config :gen_agent_server, :peers,
  enabled: System.get_env("GEN_AGENT_SERVER_PEERS", "false") == "true",
  store: System.get_env("GEN_AGENT_SERVER_PEER_STORE"),
  claude_home: System.get_env("GEN_AGENT_SERVER_CLAUDE_HOME", Path.expand("~/.claude"))

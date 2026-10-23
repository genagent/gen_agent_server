import Config

config :operator_view, OperatorViewWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4076],
  secret_key_base: String.duplicate("operator-view-test-secret-key-base-", 2),
  server: false

config :operator_view,
  token: "operator-view-test-token-0123456789",
  instances: ["alpha", "beta"],
  transport: OperatorView.FakeRelease,
  rpc_timeout_ms: 200,
  refresh_interval_ms: 60_000,
  refresh_deadline_ms: 300

config :logger, level: :warning

# The observer never starts the server application. Integration tests start it
# explicitly in this VM with model-free Echo routes, so it needs the same keys
# the server's own config/runtime.exs provides.
config :gen_agent_server,
  session_name: "server/default",
  agents: [{"echo", GenAgentEnsemble.Agents.Simple, [backend: GenAgentEnsemble.Backends.Echo]}],
  profile_file: nil,
  shared_mcp: nil

config :gen_agent_server, :peers,
  enabled: false,
  store: nil,
  claude_home: "/nonexistent/operator-view-test-claude-home"

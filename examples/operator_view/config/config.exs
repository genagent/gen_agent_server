import Config

config :phoenix, :json_library, Jason
config :phoenix, :filter_parameters, ["token", "password", "_csrf_token"]

config :operator_view, OperatorViewWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "127.0.0.1"],
  render_errors: [formats: [html: OperatorViewWeb.ErrorHTML], layout: false],
  pubsub_server: OperatorView.PubSub,
  live_view: [signing_salt: "operator-view-live"]

config :operator_view,
  transport: OperatorView.Transport.Release,
  rpc_timeout_ms: 5_000,
  refresh_interval_ms: 5_000

if config_env() == :test do
  import_config "test.exs"
end

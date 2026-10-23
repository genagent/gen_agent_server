import Config

if config_env() != :test do
  port =
    case Integer.parse(System.get_env("OPERATOR_VIEW_PORT", "4075")) do
      {port, ""} when port in 1..65_535 -> port
      _ -> raise ArgumentError, "OPERATOR_VIEW_PORT must be a TCP port number"
    end

  instances =
    System.get_env("OPERATOR_VIEW_INSTANCES", "")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))

  config :operator_view,
    token: System.get_env("OPERATOR_VIEW_TOKEN"),
    instances: instances,
    release_bin: System.get_env("OPERATOR_VIEW_RELEASE_BIN")

  # Loopback only. OperatorView.Application refuses any other bind address.
  # Sessions are signed with a fresh key per start, so a restart logs out.
  config :operator_view, OperatorViewWeb.Endpoint,
    http: [ip: {127, 0, 0, 1}, port: port],
    url: [host: "127.0.0.1", port: port],
    check_origin: ["http://127.0.0.1:#{port}", "http://localhost:#{port}"],
    secret_key_base: Base.encode64(:crypto.strong_rand_bytes(48)),
    server: true
end

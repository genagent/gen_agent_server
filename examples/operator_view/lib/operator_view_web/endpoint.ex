defmodule OperatorViewWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :operator_view

  @session_options [
    store: :cookie,
    key: "_operator_view",
    signing_salt: "operator-view-sign",
    encryption_salt: "operator-view-encrypt",
    same_site: "Strict",
    http_only: true
  ]

  socket("/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: false
  )

  plug(OperatorViewWeb.LoopbackHost)

  plug(Plug.Static,
    at: "/assets",
    from: :operator_view,
    gzip: false,
    only: ~w(operator_view.css operator_view.js)
  )

  plug(Plug.Static,
    at: "/assets/phoenix",
    from: {:phoenix, "priv/static"},
    gzip: false,
    only: ~w(phoenix.min.js)
  )

  plug(Plug.Static,
    at: "/assets/live_view",
    from: {:phoenix_live_view, "priv/static"},
    gzip: false,
    only: ~w(phoenix_live_view.min.js)
  )

  plug(Plug.Parsers, parsers: [:urlencoded], pass: ["*/*"], length: 8_000)
  plug(Plug.Head)
  plug(Plug.Session, @session_options)
  plug(OperatorViewWeb.Router)
end

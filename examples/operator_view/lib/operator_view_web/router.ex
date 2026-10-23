defmodule OperatorViewWeb.Router do
  use Phoenix.Router, helpers: false

  import Plug.Conn
  import Phoenix.Controller
  import Phoenix.LiveView.Router

  @csp "default-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'"

  pipeline(:browser) do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {OperatorViewWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers, %{"content-security-policy" => @csp})
  end

  pipeline(:operator) do
    plug(OperatorViewWeb.OperatorAuth)
  end

  scope("/") do
    pipe_through(:browser)

    get("/login", OperatorViewWeb.SessionController, :new)
    post("/login", OperatorViewWeb.SessionController, :create)
    post("/logout", OperatorViewWeb.SessionController, :delete)
  end

  scope("/") do
    pipe_through([:browser, :operator])

    live_session(:operator, on_mount: {OperatorViewWeb.OperatorAuth, :require_operator}) do
      live("/", OperatorViewWeb.OperatorLive, :index)
    end
  end
end

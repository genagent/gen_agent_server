defmodule OperatorViewWeb.OperatorAuth do
  @moduledoc """
  Local operator authentication for the example host.

  The operator supplies one token (`OPERATOR_VIEW_TOKEN`) at startup and
  enters it on the login page. A successful login stores a marker derived from
  the token in the signed, encrypted session cookie. HTTP routes check it with
  this plug and the LiveView checks it again on every mount and reconnect.
  Changing the token or restarting the observer ends existing sessions.

  An existing Phoenix host that embeds the page would use its own
  authentication instead.
  """

  import Plug.Conn

  @session_key "operator_view_auth"

  def init(opts), do: opts

  def call(conn, _opts) do
    if authenticated?(get_session(conn)) do
      conn
    else
      conn |> Phoenix.Controller.redirect(to: "/login") |> halt()
    end
  end

  def on_mount(:require_operator, _params, session, socket) do
    if authenticated?(session) do
      {:cont, socket}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: "/login")}
    end
  end

  @doc "Whether `given` is the configured operator token (constant-time comparison)."
  def valid_token?(given) when is_binary(given), do: Plug.Crypto.secure_compare(given, token())
  def valid_token?(_given), do: false

  def log_in(conn) do
    conn |> configure_session(renew: true) |> put_session(@session_key, session_marker())
  end

  def log_out(conn), do: configure_session(conn, drop: true)

  @doc false
  def session_marker do
    :hmac
    |> :crypto.mac(:sha256, token(), "operator_view session")
    |> Base.url_encode64(padding: false)
  end

  defp authenticated?(%{@session_key => marker}) when is_binary(marker) do
    Plug.Crypto.secure_compare(marker, session_marker())
  end

  defp authenticated?(_session), do: false

  defp token, do: Application.fetch_env!(:operator_view, :token)
end

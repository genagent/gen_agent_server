defmodule OperatorViewWeb.LoopbackHost do
  @moduledoc """
  Refuses HTTP requests that do not name a loopback host or do not come from
  127.0.0.1, so a rebound DNS name cannot reach the observer from a browser.
  The LiveView socket is covered separately by the endpoint's exact
  `check_origin` list and by the signed operator session.
  """

  import Plug.Conn

  @hosts ["127.0.0.1", "localhost"]

  def init(opts), do: opts

  def call(%Plug.Conn{host: host, remote_ip: ip} = conn, _opts) do
    if host in @hosts and ip == {127, 0, 0, 1} do
      conn
    else
      conn |> send_resp(400, "Bad request") |> halt()
    end
  end
end

defmodule OperatorViewWeb.SessionController do
  use Phoenix.Controller, formats: [:html]

  import Plug.Conn

  alias OperatorViewWeb.OperatorAuth

  def new(conn, _params), do: login_page(conn, 200, nil)

  def create(conn, %{"token" => token}) do
    if OperatorAuth.valid_token?(token) do
      conn |> OperatorAuth.log_in() |> redirect(to: "/")
    else
      login_page(conn, 401, "Token not accepted.")
    end
  end

  def create(conn, _params), do: login_page(conn, 401, "Token not accepted.")

  def delete(conn, _params), do: conn |> OperatorAuth.log_out() |> redirect(to: "/login")

  defp login_page(conn, status, notice) do
    csrf = Plug.HTML.html_escape(get_csrf_token())
    notice = if notice, do: ~s(<p class="error" id="login-error">#{notice}</p>), else: ""

    page = """
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <title>gen_agent_server operator view</title>
        <link rel="stylesheet" href="/assets/operator_view.css">
      </head>
      <body>
        <main class="operator">
          <h1>gen_agent_server operator view</h1>
          #{notice}
          <form action="/login" method="post">
            <input type="hidden" name="_csrf_token" value="#{csrf}">
            <label for="token">Operator token</label>
            <input id="token" name="token" type="password" autocomplete="off" required>
            <button type="submit">Log in</button>
          </form>
        </main>
      </body>
    </html>
    """

    conn |> put_status(status) |> html(page)
  end
end

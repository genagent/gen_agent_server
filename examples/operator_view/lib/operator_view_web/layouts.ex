defmodule OperatorViewWeb.Layouts do
  @moduledoc false
  use Phoenix.Component

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Phoenix.Controller.get_csrf_token()} />
        <title>gen_agent_server operator view</title>
        <link rel="stylesheet" href="/assets/operator_view.css" />
        <script defer src="/assets/phoenix/phoenix.min.js">
        </script>
        <script defer src="/assets/live_view/phoenix_live_view.min.js">
        </script>
        <script defer src="/assets/operator_view.js">
        </script>
      </head>
      <body>
        <form class="logout" action="/logout" method="post">
          <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
          <button type="submit">Log out</button>
        </form>
        {@inner_content}
      </body>
    </html>
    """
  end
end

defmodule OperatorViewWeb.ErrorHTML do
  @moduledoc false

  # Plain status text only; error pages never include request or release details.
  def render(template, _assigns), do: Phoenix.Controller.status_message_from_template(template)
end

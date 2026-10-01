defmodule Mix.Tasks.GenAgentServer do
  @moduledoc "Run a GenAgent Server command against a fresh local application instance."
  @shortdoc "List, inspect, or ask configured GenAgent backends"
  use Mix.Task

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    case GenAgentServer.CLI.run(args) do
      {:ok, output} ->
        IO.puts(output)

      {:error, :usage} ->
        Mix.raise("usage: mix gen_agent_server agents | status | ask PROVIDER PROMPT")

      {:error, reason} ->
        Mix.raise("GenAgent request failed: #{inspect(reason)}")
    end
  end
end

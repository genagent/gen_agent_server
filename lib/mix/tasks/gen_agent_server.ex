defmodule Mix.Tasks.GenAgentServer do
  @moduledoc "Run a GenAgent Server command against a fresh local application instance."
  @shortdoc "List, inspect, or ask configured GenAgent backends"
  use Mix.Task

  @impl true
  def run(args) do
    command_args =
      case args do
        ["--instance", _name | rest] -> rest
        rest -> rest
      end

    if match?([command | _] when command in ["invoke", "result", "job", "run-job"], command_args) do
      Mix.raise(
        "invoke/result/job/run-job require a running server; use mix gen_agent_server.remote"
      )
    end

    Mix.Task.run("app.start")

    case GenAgentServer.CLI.run(args) do
      {:ok, output} ->
        IO.puts(output)

      {:error, :usage} ->
        Mix.raise(
          "usage: mix gen_agent_server instances | [--instance NAME] agents | status | ask PROVIDER PROMPT"
        )

      {:error, reason} ->
        Mix.raise("GenAgent request failed: #{inspect(reason)}")
    end
  end
end

defmodule Mix.Tasks.GenAgentServer do
  @moduledoc "Run a GenAgent Server command against a fresh local application instance."
  @shortdoc "List, inspect, or ask configured GenAgent backends"
  use Mix.Task

  @impl true
  def run(args) do
    :ok = :io.setopts(:standard_io, encoding: :unicode)

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

      {:error, reason} ->
        Mix.raise("error: #{GenAgentServer.CLI.error_message(args, reason)}")
    end
  end
end

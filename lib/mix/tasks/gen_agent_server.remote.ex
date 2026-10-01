defmodule Mix.Tasks.GenAgentServer.Remote do
  @moduledoc "Send a CLI command to the running GenAgent Server release."
  @shortdoc "Ask or inspect agents in a running server release"
  use Mix.Task

  @impl true
  def run(args) do
    if args == [] do
      Mix.raise(
        "usage: mix gen_agent_server.remote instances | [--instance NAME] agents | status | ask PROVIDER PROMPT | invoke PROVIDER PROMPT | result ID"
      )
    end

    release_bin =
      System.get_env("GEN_AGENT_SERVER_RELEASE_BIN") ||
        Path.expand("_build/prod/rel/gen_agent_server/bin/gen_agent_server")

    unless File.regular?(release_bin) do
      Mix.raise("server release not found at #{release_bin}; run MIX_ENV=prod mix release")
    end

    result =
      try do
        GenAgentServer.Remote.run(release_bin, args)
      rescue
        e in ErlangError -> Mix.raise("server RPC could not start: #{Exception.message(e)}")
      end

    case result do
      {output, 0} ->
        IO.write(output)

      {:error, :timeout} ->
        Mix.raise(
          "server RPC timed out; use invoke followed by result for long work, or increase GEN_AGENT_SERVER_RPC_TIMEOUT_MS / GEN_AGENT_SERVER_ASK_RPC_TIMEOUT_MS"
        )

      {output, _status} ->
        Mix.raise("server RPC failed: #{String.trim(output)}")
    end
  end
end

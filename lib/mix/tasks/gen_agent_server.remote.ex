defmodule Mix.Tasks.GenAgentServer.Remote do
  @moduledoc "Send a CLI command to the running GenAgent Server release."
  @shortdoc "Ask or inspect agents in a running server release"
  use Mix.Task

  @impl true
  def run(args) do
    :ok = :io.setopts(:standard_io, encoding: :unicode)

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
        case GenAgentServer.Remote.decode_response(output) do
          {:ok, text} -> IO.puts(text)
          {:error, :invalid_response} -> Mix.raise("server RPC returned an invalid response")
          {:error, message} -> Mix.raise("error: #{message}")
        end

      {:error, :timeout} ->
        Mix.raise(timeout_message(args))

      {output, _status} ->
        Mix.raise("server RPC failed: #{String.trim(output)}")
    end
  end

  defp timeout_message(["--instance", _instance, command | _]), do: timeout_message(command)
  defp timeout_message([command | _]), do: timeout_message(command)

  defp timeout_message("ask"),
    do:
      "server ask RPC timed out; use invoke followed by result for future long work, or increase GEN_AGENT_SERVER_ASK_RPC_TIMEOUT_MS"

  defp timeout_message("invoke"),
    do:
      "server invoke RPC timed out before an ID was returned; check server logs before retrying to avoid duplicate work, or increase GEN_AGENT_SERVER_RPC_TIMEOUT_MS"

  defp timeout_message("result"),
    do:
      "server result RPC timed out; retry result with the same ID, or increase GEN_AGENT_SERVER_RPC_TIMEOUT_MS"

  defp timeout_message(_command),
    do:
      "server RPC timed out; check release connectivity and logs, or increase GEN_AGENT_SERVER_RPC_TIMEOUT_MS"
end

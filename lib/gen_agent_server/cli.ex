defmodule GenAgentServer.CLI do
  @moduledoc """
  Small local command entry point for inspecting and asking configured agents.

  Run with `mix gen_agent_server ...` or from a running release with `rpc`.
  """

  def run(["agents"]) do
    with {:ok, names} <- GenAgentServer.agents(), do: {:ok, Enum.join(names, "\n")}
  end

  def run(["status"]) do
    with {:ok, status} <- GenAgentServer.status(), do: {:ok, inspect(status, pretty: true)}
  end

  def run(["ask", agent | words]) when words != [] do
    with {:ok, response} <- GenAgentServer.ask(agent, Enum.join(words, " ")) do
      {:ok, response.text}
    end
  end

  def run(_args), do: {:error, :usage}

  def main(args) do
    case run(args) do
      {:ok, output} ->
        IO.puts(output)
        :ok

      {:error, :usage} ->
        raise ArgumentError, "usage: gen_agent_server agents | status | ask PROVIDER PROMPT"

      {:error, reason} ->
        raise RuntimeError, "GenAgent request failed: #{inspect(reason)}"
    end
  end
end

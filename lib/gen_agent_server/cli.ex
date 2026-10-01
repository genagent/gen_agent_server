defmodule GenAgentServer.CLI do
  @moduledoc """
  Small local command entry point for inspecting and asking configured agents.

  Run with `mix gen_agent_server ...` or from a running release with `rpc`.
  """

  def run(args, source \\ :local_cli)

  def run(["agents"], _source) do
    with {:ok, names} <- GenAgentServer.agents(), do: {:ok, Enum.join(names, "\n")}
  end

  def run(["status"], _source) do
    with {:ok, status} <- GenAgentServer.status(), do: {:ok, inspect(status, pretty: true)}
  end

  def run(["ask", agent | words], source) when words != [] do
    with {:ok, response} <- GenAgentServer.ask(agent, Enum.join(words, " "), source: source) do
      {:ok, response.text}
    end
  end

  def run(["invoke", agent | words], source) when words != [] do
    GenAgentServer.invoke(GenAgentServer.session_name(), agent, Enum.join(words, " "),
      source: source
    )
  end

  def run(["result", id], _source) do
    case GenAgentServer.result(id) do
      {:ok, :pending} -> {:ok, "pending"}
      {:ok, :completed, response} -> {:ok, response.text}
      {:ok, :failed, reason} -> {:error, reason}
      error -> error
    end
  end

  def run(_args, _source), do: {:error, :usage}

  def main(args, source \\ :local_cli) do
    case run(args, source) do
      {:ok, output} ->
        IO.puts(output)
        :ok

      {:error, :usage} ->
        raise ArgumentError,
              "usage: gen_agent_server agents | status | ask PROVIDER PROMPT | invoke PROVIDER PROMPT | result ID"

      {:error, reason} ->
        raise RuntimeError, "GenAgent request failed: #{inspect(reason)}"
    end
  end
end

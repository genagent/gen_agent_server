defmodule GenAgentServer do
  @moduledoc """
  Local control API for this runnable GenAgent application.

  The application owns one volatile Switchboard session. Each configured
  backend has a separate provider session. A process or VM restart loses
  in-memory turns, results, and session state.
  """

  def session_name, do: Application.fetch_env!(:gen_agent_server, :session_name)

  def agents do
    with {:ok, %{agents: names}} <- status(), do: {:ok, Enum.sort(names)}
  end

  def status, do: GenAgentEnsemble.status(session_name())

  def ask(agent, prompt, opts \\ []) when is_binary(agent) and is_binary(prompt) do
    opts = opts |> Keyword.put_new(:timeout, :infinity) |> Keyword.put(:agent, agent)
    GenAgentEnsemble.ask(session_name(), prompt, opts)
  end
end

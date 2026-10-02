defmodule GenAgentServer.Agents.Role do
  @moduledoc """
  A single-turn agent that prepends an optional role preamble to every prompt.

  Backends name the system prompt differently (`:system_prompt` for Claude,
  none for Codex), so the role is sent as prompt text in `pre_turn/2`. All
  other options are forwarded to the backend unchanged, as with
  `GenAgentEnsemble.Agents.Simple`.
  """

  use GenAgent

  @impl true
  def init_agent(opts) do
    {role, backend_opts} = Keyword.pop(opts, :role)
    {:ok, backend_opts, %{role: role}}
  end

  @impl true
  def pre_turn(prompt, %{role: role} = state) when is_binary(role) and role != "" do
    {:ok, role <> "\n\n" <> prompt, state}
  end

  def pre_turn(prompt, state), do: {:ok, prompt, state}

  @impl true
  def handle_response(_ref, _response, state), do: {:noreply, state}
end

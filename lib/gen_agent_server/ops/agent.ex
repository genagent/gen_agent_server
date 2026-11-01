defmodule GenAgentServer.Ops.Agent do
  @moduledoc """
  The `agent` operations: start or continue a session and read its results.

  Spike for genagent/gen_agent_server#140. Sessions run through
  `GenAgentServer.Session`, directly over the CLI wrappers.
  """

  import GenAgentServer.Ops, only: [op: 5, req: 3, opt: 3, jsonable: 1, normalize: 1]

  alias GenAgentServer.Session

  @create_only ~w(name cwd provider model effort access)

  def operations do
    [
      op(
        "agent",
        "Start an agent session, or continue one with session_id, and submit a prompt. " <>
          "Returns the session and invocation ids, and the result if it ends within wait_ms.",
        true,
        [
          req("prompt", :string, "Task or message for the agent"),
          opt("session_id", :string, "Continue this session. Omit to start a new one."),
          opt("name", :string, "Id for a new session (default: generated)"),
          opt("cwd", :string, "Working directory for a new session (required to start one)"),
          opt("provider", :string, "claude or codex (default codex)")
          |> Map.put(:schema, %{"enum" => ["claude", "codex"]}),
          opt("model", :string, "Model for a new session (default: the CLI's)"),
          opt("effort", :string, "Reasoning effort for a new session"),
          opt(
            "access",
            :string,
            "Narrow a new session's access. Default inherit. " <>
              "claude: a permission mode; codex: read_only or workspace_write."
          ),
          wait_ms()
        ],
        &agent/1
      ),
      op(
        "agent_result",
        "Read an invocation's result, waiting up to wait_ms for it to end. " <>
          "Defaults to the session's latest invocation.",
        false,
        [
          req("session_id", :string, "Session id"),
          opt("invocation_id", :string, "Invocation id (default: latest)"),
          wait_ms()
        ],
        fn a ->
          a["session_id"]
          |> Session.result(a["invocation_id"], Map.get(a, "wait_ms", 0))
          |> present(a["session_id"])
        end
      ),
      op(
        "agent_cancel",
        "Cancel a session's running turn and drop its queued prompts. The session stays.",
        true,
        [req("session_id", :string, "Session id")],
        fn a ->
          with {:ok, ids} <- Session.cancel(a["session_id"]),
               do: {:ok, %{session_id: a["session_id"], cancelled: ids}}
        end
      ),
      op(
        "agent_stop",
        "Stop a session. Its held results are discarded.",
        true,
        [req("session_id", :string, "Session id")],
        fn a ->
          with :ok <- Session.stop(a["session_id"]),
               do: {:ok, %{session_id: a["session_id"], stopped: true}}
        end
      ),
      op("agent_sessions", "List agent sessions.", false, [], fn _ ->
        sessions =
          for id <- Session.list(),
              {:ok, description} <- [Session.describe(id)],
              do: jsonable(description)

        {:ok, %{sessions: sessions}}
      end)
    ]
  end

  defp wait_ms do
    opt("wait_ms", :integer, "Wait for the result, 0 to 600000 milliseconds (default 0)")
    |> Map.put(:schema, %{"minimum" => 0, "maximum" => 600_000})
  end

  defp agent(%{"session_id" => id} = a) do
    case Enum.filter(@create_only, &Map.has_key?(a, &1)) do
      [] ->
        submit(id, a)

      given ->
        {:error,
         %{
           code: "invalid_args",
           message: "#{Enum.join(given, ", ")} apply only when starting a session"
         }}
    end
  end

  defp agent(a) do
    with {:ok, cwd} <- fetch_cwd(a),
         {:ok, id} <-
           Session.start(
             id: Map.get_lazy(a, "name", &generated_id/0),
             provider: Map.get(a, "provider", "codex"),
             cwd: cwd,
             model: a["model"],
             effort: a["effort"],
             access: a["access"]
           ) do
      submit(id, a)
    end
  end

  defp submit(id, a) do
    with {:ok, invocation_id} <- Session.submit(id, a["prompt"]) do
      id
      |> Session.result(invocation_id, Map.get(a, "wait_ms", 0))
      |> present(id)
    end
  end

  defp present({:ok, result}, id) do
    result =
      case result do
        %{status: :failed, error: reason} -> %{result | error: normalize(reason)}
        _ -> result
      end

    {:ok, result |> Map.put(:session_id, id) |> jsonable()}
  end

  defp present(error, _id), do: error

  defp fetch_cwd(%{"cwd" => cwd}), do: {:ok, cwd}

  defp fetch_cwd(_a),
    do: {:error, %{code: "invalid_args", message: "cwd is required to start a session"}}

  defp generated_id, do: "s-" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
end

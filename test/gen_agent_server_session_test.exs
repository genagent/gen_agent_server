defmodule GenAgentServer.SessionTest do
  use ExUnit.Case, async: false

  alias GenAgentServer.Ops

  # A fake codex: logs its argv, reads the prompt from stdin, and prints a
  # thread, one agent message per turn, and usage. `sleep` in the prompt holds
  # the turn open.
  @script """
  #!/bin/sh
  echo "$@" >> "$FAKE_CODEX_LOG"
  prompt=$(cat)
  case "$prompt" in *sleep*) sleep 5 ;; esac
  echo '{"type":"thread.started","thread_id":"thread-1"}'
  printf '{"type":"item.completed","item":{"id":"m","type":"agent_message","text":"echo: %s"}}\\n' "$prompt"
  echo '{"type":"turn.completed","usage":{"input_tokens":3,"output_tokens":2}}'
  """

  setup do
    dir = Path.join(System.tmp_dir!(), "gas-session-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    binary = Path.join(dir, "codex")
    File.write!(binary, @script)
    File.chmod!(binary, 0o755)
    log = Path.join(dir, "argv.log")

    previous = Application.fetch_env(:gen_agent_server, :provider_overrides)

    Application.put_env(:gen_agent_server, :provider_overrides, %{
      "codex" => [binary: binary, env: [{"FAKE_CODEX_LOG", log}]]
    })

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:gen_agent_server, :provider_overrides, value)
        :error -> Application.delete_env(:gen_agent_server, :provider_overrides)
      end

      for id <- GenAgentServer.Session.list(), do: GenAgentServer.Session.stop(id)
      File.rm_rf!(dir)
    end)

    %{dir: dir, log: log}
  end

  test "a new session runs a turn and a continuation resumes the provider session",
       %{dir: dir, log: log} do
    assert {:ok, first} =
             Ops.call("agent", %{
               "prompt" => "hello",
               "cwd" => dir,
               "name" => "s1",
               "wait_ms" => 5_000
             })

    assert %{"status" => "completed", "text" => "echo: hello", "session_id" => "s1"} = first
    assert first["invocation_id"] == "s1/1"
    assert first["usage"] == %{"input_tokens" => 3, "output_tokens" => 2}

    assert {:ok, second} =
             Ops.call("agent", %{"prompt" => "again", "session_id" => "s1", "wait_ms" => 5_000})

    assert %{"status" => "completed", "text" => "echo: again", "invocation_id" => "s1/2"} = second

    [turn1, turn2] = log |> File.read!() |> String.split("\n", trim: true)
    refute turn1 =~ "resume"
    assert turn2 =~ "resume"
    assert turn2 =~ "thread-1"

    assert {:ok, %{sessions: [session]}} = Ops.call("agent_sessions")

    assert %{"provider_session_id" => "thread-1", "completed" => 2, "access" => "inherit"} =
             session
  end

  test "without wait_ms the call returns pending and agent_result waits", %{dir: dir} do
    assert {:ok, %{"status" => "pending", "invocation_id" => id}} =
             Ops.call("agent", %{"prompt" => "hi", "cwd" => dir, "name" => "s2"})

    assert {:ok, %{"status" => "completed", "invocation_id" => ^id}} =
             Ops.call("agent_result", %{"session_id" => "s2", "wait_ms" => 5_000})
  end

  test "a prompt during a turn queues and cancel drops both", %{dir: dir} do
    assert {:ok, %{"status" => "pending"}} =
             Ops.call("agent", %{"prompt" => "sleep", "cwd" => dir, "name" => "s3"})

    assert {:ok, %{"status" => "pending", "invocation_id" => "s3/2"}} =
             Ops.call("agent", %{"prompt" => "next", "session_id" => "s3"})

    assert {:ok, %{cancelled: ["s3/2", "s3/1"]}} =
             Ops.call("agent_cancel", %{"session_id" => "s3"})

    assert {:ok, %{"status" => "cancelled"}} =
             Ops.call("agent_result", %{"session_id" => "s3", "invocation_id" => "s3/1"})
  end

  test "continuing a session rejects options that apply only to new sessions", %{dir: dir} do
    assert {:ok, _} =
             Ops.call("agent", %{
               "prompt" => "hi",
               "cwd" => dir,
               "name" => "s4",
               "wait_ms" => 5_000
             })

    assert {:error, %{code: "invalid_args", message: message}} =
             Ops.call("agent", %{"prompt" => "x", "session_id" => "s4", "model" => "m"})

    assert message =~ "model"
  end

  test "errors for missing cwd, unknown sessions and invalid access", %{dir: dir} do
    assert {:error, %{code: "invalid_args"}} = Ops.call("agent", %{"prompt" => "hi"})

    assert {:error, %{code: "session_not_found"}} =
             Ops.call("agent", %{"prompt" => "hi", "session_id" => "missing"})

    assert {:error, %{message: message}} =
             Ops.call("agent", %{"prompt" => "hi", "cwd" => dir, "access" => "everything"})

    assert message =~ "invalid_option"
  end

  test "a narrowed codex session keeps its sandbox on resumed turns", %{dir: dir, log: log} do
    args = %{"cwd" => dir, "name" => "s5", "access" => "read_only", "effort" => "low"}

    assert {:ok, %{"status" => "completed"}} =
             Ops.call("agent", Map.merge(args, %{"prompt" => "one", "wait_ms" => 5_000}))

    assert {:ok, %{"status" => "completed"}} =
             Ops.call("agent", %{"prompt" => "two", "session_id" => "s5", "wait_ms" => 5_000})

    [turn1, turn2] = log |> File.read!() |> String.split("\n", trim: true)
    assert turn1 =~ "read-only"
    assert turn2 =~ "read-only"
    assert turn1 =~ ~s(model_reasoning_effort="low")
    assert turn2 =~ ~s(model_reasoning_effort="low")
  end
end

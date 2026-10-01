defmodule GenAgentServer.RemoteTest do
  use ExUnit.Case, async: false

  alias GenAgentServer.Remote

  setup do
    dir = Path.join(System.tmp_dir!(), "gen-agent-rpc-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  test "a slow RPC within its configured bound succeeds", %{dir: dir} do
    release = script(dir, "slow", "sleep 0.1\nprintf 'ready\\n'")
    assert {"ready\n", 0} = Remote.run(release, ["status"], timeout_ms: 1_000)
  end

  test "control and ask commands use separate wait limits", %{dir: dir} do
    release = script(dir, "slow", "sleep 0.1\nprintf 'ready\\n'")
    old_control = System.get_env("GEN_AGENT_SERVER_RPC_TIMEOUT_MS")
    old_ask = System.get_env("GEN_AGENT_SERVER_ASK_RPC_TIMEOUT_MS")
    System.put_env("GEN_AGENT_SERVER_RPC_TIMEOUT_MS", "30")
    System.put_env("GEN_AGENT_SERVER_ASK_RPC_TIMEOUT_MS", "1000")

    try do
      assert {:error, :timeout} = Remote.run(release, ["status"])

      assert {"ready\n", 0} =
               Remote.run(release, ["--instance", "work", "ask", "codex", "prompt"])
    after
      restore_env("GEN_AGENT_SERVER_RPC_TIMEOUT_MS", old_control)
      restore_env("GEN_AGENT_SERVER_ASK_RPC_TIMEOUT_MS", old_ask)
    end
  end

  test "timeout terminates the RPC and its child process", %{dir: dir} do
    child_file = Path.join(dir, "child.pid")

    release =
      script(dir, "stalled", "sleep 60 &\necho $! > #{child_file}\nwait")

    assert {:error, :timeout} =
             Remote.run(release, ["invoke", "codex", "prompt"], timeout_ms: 200)

    child_pid = child_file |> File.read!() |> String.trim() |> String.to_integer()

    assert eventually(fn -> not running?(child_pid) end)
  end

  test "the remote task reports an actionable timeout", %{dir: dir} do
    release = script(dir, "stalled", "sleep 60")
    old_release = System.get_env("GEN_AGENT_SERVER_RELEASE_BIN")
    old_timeout = System.get_env("GEN_AGENT_SERVER_RPC_TIMEOUT_MS")
    System.put_env("GEN_AGENT_SERVER_RELEASE_BIN", release)
    System.put_env("GEN_AGENT_SERVER_RPC_TIMEOUT_MS", "30")

    try do
      assert_raise Mix.Error, ~r/server RPC timed out; use invoke followed by result/, fn ->
        Mix.Tasks.GenAgentServer.Remote.run(["status"])
      end
    after
      restore_env("GEN_AGENT_SERVER_RELEASE_BIN", old_release)
      restore_env("GEN_AGENT_SERVER_RPC_TIMEOUT_MS", old_timeout)
    end
  end

  defp script(dir, name, body) do
    path = Path.join(dir, name)
    File.write!(path, "#!/bin/sh\n#{body}\n")
    File.chmod!(path, 0o755)
    path
  end

  defp running?(pid) do
    case System.cmd("ps", ["-o", "stat=", "-p", Integer.to_string(pid)]) do
      {status, 0} -> not String.starts_with?(String.trim(status), "Z")
      _ -> false
    end
  end

  defp eventually(fun, attempts \\ 20)
  defp eventually(fun, 0), do: fun.()

  defp eventually(fun, attempts) do
    if fun.() do
      true
    else
      Process.sleep(25)
      eventually(fun, attempts - 1)
    end
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end

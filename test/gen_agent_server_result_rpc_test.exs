defmodule GenAgentServer.ResultRPCTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  test "remote ops forwards a wait plus the RPC margin" do
    release = Path.join(System.tmp_dir!(), "result-rpc-#{System.unique_integer([:positive])}")

    File.write!(
      release,
      "#!/bin/sh\nprintf '{\"ok\":true,\"data\":{\"status\":\"pending\"}}\\n'\n"
    )

    File.chmod!(release, 0o755)
    old = System.get_env("GEN_AGENT_SERVER_RELEASE_BIN")
    System.put_env("GEN_AGENT_SERVER_RELEASE_BIN", release)

    on_exit(fn ->
      File.rm!(release)

      if old,
        do: System.put_env("GEN_AGENT_SERVER_RELEASE_BIN", old),
        else: System.delete_env("GEN_AGENT_SERVER_RELEASE_BIN")
    end)

    Code.ensure_loaded!(GenAgentServer.Ops.Remote)
    :erlang.trace_pattern({GenAgentServer.Ops.Remote, :call, 4}, true, [])

    try do
      for {flags, expected} <- [
            {[], 30_000},
            {["--wait_ms", "600000"], 630_000},
            {["--wait-ms", "10"], 30_010}
          ] do
        task =
          Task.async(fn ->
            receive do
              :go ->
                capture_io(fn ->
                  Mix.Tasks.GenAgentServer.Ops.run(["result", "--id", "id", "--remote"] ++ flags)
                end)
            end
          end)

        :erlang.trace(task.pid, true, [:call, {:tracer, self()}])
        send(task.pid, :go)

        assert_receive {:trace, _, :call,
                        {GenAgentServer.Ops.Remote, :call,
                         [^release, "result", _args, [timeout_ms: ^expected]]}},
                       1_000

        assert Task.await(task) =~ "pending"
      end
    after
      :erlang.trace_pattern({GenAgentServer.Ops.Remote, :call, 4}, false, [])
    end
  end
end

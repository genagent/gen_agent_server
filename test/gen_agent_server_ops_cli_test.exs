defmodule GenAgentServer.OpsCLITest do
  use ExUnit.Case, async: false

  test "the documented underscore timeout works for ask and run_pattern" do
    for flag <- ["--timeout_ms", "--timeout-ms", "--timeout_ms=1000"] do
      args = ["gen_agent_server.ops", "ask", "--agent", "echo", "--prompt", "flag"]
      args = if String.contains?(flag, "="), do: args ++ [flag], else: args ++ [flag, "1000"]
      assert %{"status" => "completed", "text" => "echo: flag"} = ok!(args)
    end

    spec = Jason.encode!(%{"pattern" => "pipeline", "stages" => [%{"provider" => "echo"}]})

    assert %{"results" => [%{"status" => "completed", "text" => "echo: pattern"}]} =
             ok!([
               "gen_agent_server.ops",
               "run_pattern",
               "--spec",
               spec,
               "--prompts",
               "pattern",
               "--timeout_ms",
               "1000"
             ])
  end

  test "the underscore timeout reaches the remote operation" do
    dir = Path.join(System.tmp_dir!(), "gen-agent-ops-cli-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    release = Path.join(dir, "release")
    File.write!(release, "#!/bin/sh\n[ \"$1\" = rpc ] || exit 64\nexec mix run -e \"$2\"\n")
    File.chmod!(release, 0o755)

    assert %{"status" => "completed", "text" => "echo: remote"} =
             ok!(
               [
                 "gen_agent_server.ops",
                 "ask",
                 "--agent",
                 "echo",
                 "--prompt",
                 "remote",
                 "--timeout_ms",
                 "1000",
                 "--remote"
               ],
               [{"GEN_AGENT_SERVER_RELEASE_BIN", release}]
             )
  end

  test "an unknown switch still fails before submitting work" do
    {output, status} = command(["gen_agent_server.ops", "ask", "--bogus_flag", "1"])
    assert status != 0
    assert output =~ "unexpected arguments"
  end

  defp ok!(args, env \\ []) do
    {output, 0} = command(args, env)
    Jason.decode!(output)
  end

  defp command(args, env \\ []) do
    System.cmd("mix", args,
      env: [{"MIX_ENV", "test"}, {"MIX_QUIET", "1"} | env],
      stderr_to_stdout: true
    )
  end
end

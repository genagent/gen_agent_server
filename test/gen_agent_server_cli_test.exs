defmodule GenAgentServer.CLITest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  setup do
    dir = Path.join(System.tmp_dir!(), "gen-agent-cli-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  test "local Mix CLI preserves UTF-8 output through a pipe" do
    assert {"echo: it’s → done\n", 0} = mix(["gen_agent_server", "ask", "echo", "it’s → done"])
  end

  test "local Mix CLI reports ordinary errors on one line" do
    {output, status} = mix(["gen_agent_server", "--instance", "missing", "agents"])
    assert status != 0
    assert_one_line_error(output, "instance missing not found")

    {output, status} = mix(["gen_agent_server", "ask", "missing", "hello"])
    assert status != 0
    assert_one_line_error(output, "agent missing not found in instance server/default")

    {output, status} = mix(["gen_agent_server", "bad-command"])
    assert status != 0
    assert_one_line_error(output, "usage: gen_agent_server")
  end

  test "direct CLI.main fails with nonzero status for ordinary errors" do
    {output, status} =
      mix(["run", "-e", ~s|GenAgentServer.CLI.main(["result", "inv-12"])|])

    assert status != 0
    assert_one_line_error(output, "invocation inv-12 not found in instance server/default")
  end

  test "remote Mix CLI preserves UTF-8 output through the RPC envelope", %{dir: dir} do
    release = rpc_script(dir)

    assert {"echo: it’s → done\n", 0} =
             mix(["gen_agent_server.remote", "ask", "echo", "it’s → done"], release)
  end

  test "remote Mix CLI reports expected RPC errors without server stack traces", %{dir: dir} do
    release = rpc_script(dir)

    for {args, expected} <- [
          {["--instance", "server/default", "result", "inv-12"],
           "invocation inv-12 not found in instance server/default"},
          {["--instance", "missing", "agents"], "instance missing not found"},
          {["job", "missing"], "job missing not found"},
          {["bad-command"], "usage: gen_agent_server"}
        ] do
      {output, status} = mix(["gen_agent_server.remote" | args], release)
      assert status != 0
      assert_one_line_error(output, expected)
    end
  end

  test "a busy instance returns an ordinary remote CLI error" do
    name = "busy-#{System.unique_integer([:positive])}"

    agents = [
      {"slow", GenAgentEnsemble.Agents.Simple,
       [backend: GenAgentEnsemble.Backends.Echo, delay_ms: 1_000]}
    ]

    assert {:ok, _pid} = GenAgentServer.start_instance(name, agents, max_in_flight: 1)
    on_exit(fn -> GenAgentServer.stop_instance(name) end)
    assert {:ok, _id} = GenAgentServer.invoke(name, "slow", "first")

    output =
      capture_io(fn ->
        assert :ok =
                 GenAgentServer.CLI.remote_main(["--instance", name, "invoke", "slow", "second"])
      end)

    assert {:error, message} = GenAgentServer.Remote.decode_response(output)
    assert message == "instance #{name} is busy"
  end

  test "unknown-agent errors name the searched instance" do
    assert GenAgentServer.CLI.error_message(
             ["--instance", "work", "ask", "other", "hello"],
             {:unknown_agent, "other"}
           ) == "agent other not found in instance work"
  end

  defp mix(args, release \\ nil) do
    env = [{"MIX_ENV", "test"}, {"MIX_QUIET", "1"}]
    env = if release, do: [{"GEN_AGENT_SERVER_RELEASE_BIN", release} | env], else: env
    System.cmd("mix", args, env: env, stderr_to_stdout: true)
  end

  defp rpc_script(dir) do
    path = Path.join(dir, "release")
    File.write!(path, "#!/bin/sh\n[ \"$1\" = rpc ] || exit 64\nexec mix run -e \"$2\"\n")
    File.chmod!(path, 0o755)
    path
  end

  defp assert_one_line_error(output, expected) do
    assert output =~ "error: #{expected}"
    assert length(String.split(output, "\n", trim: true)) == 1
    refute output =~ "stacktrace:"
    refute output =~ "lib/gen_agent_server/cli.ex"
  end
end

defmodule GenAgentServerTest do
  use ExUnit.Case
  import ExUnit.CaptureIO

  test "application serves the Echo agent through one local API" do
    assert {:ok, ["echo"]} = GenAgentServer.agents()
    assert {:ok, %{text: "echo: hello"}} = GenAgentServer.ask("echo", "hello")
    assert {:error, {:unknown_agent, "missing"}} = GenAgentServer.ask("missing", "hello")
  end

  test "CLI lists agents and routes an ask" do
    assert capture_io(fn -> assert :ok = GenAgentServer.CLI.main(["agents"]) end) == "echo\n"

    assert capture_io(fn -> assert :ok = GenAgentServer.CLI.main(["ask", "echo", "hello"]) end) ==
             "echo: hello\n"
  end

  test "remote command encodes quoted prompts as data" do
    prompt = ~S|What's "next"; #{GenAgentServer.stop()}|
    expression = GenAgentServer.Remote.expression(["ask", "echo", prompt])

    assert capture_io(fn -> Code.eval_string(expression) end) == "echo: #{prompt}\n"
  end

  test "remote command reports an inaccessible release executable" do
    previous = System.get_env("GEN_AGENT_SERVER_RELEASE_BIN")
    System.put_env("GEN_AGENT_SERVER_RELEASE_BIN", Path.expand("README.md"))

    try do
      assert_raise Mix.Error, ~r/server RPC could not start/, fn ->
        Mix.Tasks.GenAgentServer.Remote.run(["agents"])
      end
    after
      if previous do
        System.put_env("GEN_AGENT_SERVER_RELEASE_BIN", previous)
      else
        System.delete_env("GEN_AGENT_SERVER_RELEASE_BIN")
      end
    end
  end
end

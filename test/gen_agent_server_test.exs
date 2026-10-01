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
end

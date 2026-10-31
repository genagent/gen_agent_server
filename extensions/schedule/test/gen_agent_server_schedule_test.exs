defmodule GenAgentServer.ScheduleTest do
  use ExUnit.Case, async: false

  alias GenAgentServer.{CLI, Ops}

  test "job commands and operations are served by the extension" do
    assert {:ok, ""} = CLI.run(["jobs"])
    assert {:error, {:message, "job missing not found"} = reason} = CLI.run(["job", "missing"])
    assert CLI.error_message(["job", "missing"], reason) == "job missing not found"
    assert {:error, {:message, "job missing not found"}} = CLI.run(["run-job", "missing"])

    assert {:ok, %{jobs: []}} = Ops.call("jobs")
    assert {:error, %{code: "unknown_job"}} = Ops.call("run_job", %{"name" => "missing"})
  end
end

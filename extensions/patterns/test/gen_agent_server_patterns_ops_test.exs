defmodule GenAgentServer.PatternsOpsTest do
  use ExUnit.Case, async: false

  alias GenAgentServer.Ops

  test "run_pattern runs a spec and cleans up its instance" do
    spec = %{
      "pattern" => "pipeline",
      "stages" => [%{"provider" => "echo"}, %{"provider" => "echo"}]
    }

    assert {:ok, %{"results" => [%{"status" => "completed", "text" => "echo: echo: a"}]} = report} =
             Ops.call("run_pattern", %{"spec" => spec, "prompts" => ["a"]})

    assert eventually(fn -> report["instance"] not in GenAgentServer.instances() end)

    assert {:error, %{code: "unknown_pattern"}} =
             Ops.call("run_pattern", %{"spec" => %{"pattern" => "mesh"}, "prompts" => ["a"]})

    assert {:error, %{code: "invalid_role"}} =
             Ops.call("run_pattern", %{
               "spec" => %{
                 "pattern" => "consensus",
                 "agents" => [%{"provider" => "echo", "role" => 7}, %{"provider" => "echo"}],
                 "verdicts" => ["yes"]
               },
               "prompts" => ["a"]
             })
  end

  test "the documented underscore timeout works for run_pattern" do
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

  defp ok!(args, env \\ []) do
    {output, 0} = command(args, env)
    Jason.decode!(output)
  end

  defp command(args, env) do
    System.cmd("mix", args,
      env: [{"MIX_ENV", "test"}, {"MIX_QUIET", "1"} | env],
      stderr_to_stdout: true
    )
  end

  defp eventually(fun, attempts \\ 100) do
    cond do
      fun.() -> true
      attempts == 0 -> false
      true -> Process.sleep(10) && eventually(fun, attempts - 1)
    end
  end
end

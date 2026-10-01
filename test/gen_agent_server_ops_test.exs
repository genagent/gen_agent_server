defmodule GenAgentServer.OpsTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias GenAgentServer.Ops

  test "every operation has a summary, typed params, and a valid JSON schema" do
    for op <- Ops.operations() do
      assert op.summary != ""
      assert is_boolean(op.mutates)
      schema = Ops.json_schema(op)
      assert schema["type"] == "object"
      assert Enum.all?(schema["required"], &Map.has_key?(schema["properties"], &1))
      assert {:ok, _} = Jason.encode(schema)
    end
  end

  test "read operations are marked as not mutating" do
    reads = for op <- Ops.operations(), not op.mutates, do: op.name
    assert "instances" in reads and "result" in reads and "status" in reads
    refute "invoke" in reads or "run_pattern" in reads or "stop_instance" in reads
  end

  test "validates arguments before running" do
    assert {:error, %{code: "unknown_operation"}} = Ops.call("explode", %{})

    assert {:error, %{code: "invalid_args", message: msg}} =
             Ops.call("invoke", %{"agent" => "echo"})

    assert msg =~ "prompt"

    assert {:error, %{code: "invalid_args", message: "unknown arguments: bogus"}} =
             Ops.call("instances", %{"bogus" => 1})

    assert {:error, %{code: "invalid_args"}} =
             Ops.call("ask", %{"agent" => "echo", "prompt" => "x", "timeout_ms" => "soon"})
  end

  test "ask, invoke, and result return JSON-safe data on the default instance" do
    assert {:ok, %{status: "completed", text: "echo: hi"} = data} =
             Ops.call("ask", %{"agent" => "echo", "prompt" => "hi"})

    assert {:ok, _} = Jason.encode(data)

    assert {:ok, %{id: id}} = Ops.call("invoke", %{"agent" => "echo", "prompt" => "later"})

    assert eventually(fn ->
             match?({:ok, %{status: "completed"}}, Ops.call("result", %{"id" => id}))
           end)

    assert {:error, %{code: "not_found"}} = Ops.call("result", %{"id" => "inv-missing"})

    assert {:error, %{code: "unknown_agent"}} =
             Ops.call("ask", %{"agent" => "nobody", "prompt" => "x"})
  end

  test "status is JSON-safe and reports a missing instance as an error" do
    assert {:ok, status} = Ops.call("status", %{})
    assert {:ok, _} = Jason.encode(status)
    assert status["strategy"] == "GenAgentEnsemble.Strategies.Switchboard"
    assert {:error, %{code: "instance_not_found"}} = Ops.call("status", %{"instance" => "nope"})
  end

  test "run_pattern runs a spec and cleans up its instance" do
    spec = %{
      "pattern" => "pipeline",
      "stages" => [%{"provider" => "echo"}, %{"provider" => "echo"}]
    }

    assert {:ok, %{"results" => [%{"status" => "completed", "text" => "echo: echo: a"}]} = report} =
             Ops.call("run_pattern", %{"spec" => spec, "prompts" => ["a"]})

    refute report["instance"] in GenAgentServer.instances()

    assert {:error, %{code: "unknown_pattern"}} =
             Ops.call("run_pattern", %{"spec" => %{"pattern" => "mesh"}, "prompts" => ["a"]})
  end

  test "the remote entry point prints one JSON envelope" do
    expression = Ops.Remote.expression("ask", %{"agent" => "echo", "prompt" => "it’s"})
    output = capture_io(fn -> Code.eval_string(expression) end)
    assert %{"ok" => true, "data" => %{"text" => "echo: it’s"}} = Jason.decode!(output)

    output = capture_io(fn -> Ops.Remote.main("result", ~s({"id":"x"})) end)
    assert %{"ok" => false, "error" => %{"code" => "not_found"}} = Jason.decode!(output)
  end

  defp eventually(fun, attempts \\ 100) do
    cond do
      fun.() -> true
      attempts == 0 -> false
      true -> Process.sleep(10) && eventually(fun, attempts - 1)
    end
  end
end

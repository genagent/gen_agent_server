defmodule GenAgentServer.CancelOpsTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO
  alias GenAgentServer.{MCP, Ops, Remote}

  defmodule Backend do
    @behaviour GenAgent.Backend
    def start_session(opts), do: {:ok, opts[:target]}

    def prompt(target, prompt) do
      send(target, {:entered, prompt, self()})

      receive do
        :finish -> {:ok, [GenAgent.Event.new(:result, %{text: prompt})], target}
      end
    end

    def update_session(session, _), do: session
    def terminate_session(_), do: :ok
  end

  setup do
    names = for _ <- 1..2, do: "cancel-ops-#{System.unique_integer([:positive])}"

    for name <- names do
      agents = [{"worker", GenAgentEnsemble.Agents.Simple, [backend: Backend, target: self()]}]
      assert {:ok, _} = GenAgentServer.start_instance(name, agents, poll_interval_ms: 1)
      on_exit(fn -> GenAgentServer.stop_instance(name) end)
    end

    {:ok, client} = Snodo.Client.direct(MCP.Server.runtime())
    %{names: names, client: client}
  end

  test "Ops requires exact scope and preserves pending, terminal, unknown and repeated IDs", %{
    names: [name, other]
  } do
    for args <- [
          %{},
          %{"instance" => name},
          %{"id" => "unknown"},
          %{"instance" => "", "id" => "x"},
          %{"instance" => name, "id" => ""}
        ] do
      assert {:error, %{code: "invalid_args"}} = Ops.call("cancel", args)
    end

    assert {:ok, op} = Ops.fetch("cancel")
    assert op.mutates
    assert Ops.json_schema(op)["required"] == ["instance", "id"]
    assert {:ok, id} = GenAgentServer.invoke(name, "worker", "blocked")
    assert_receive {:entered, "blocked", _}
    assert {:ok, other_id} = GenAgentServer.invoke(other, "worker", "other")
    assert_receive {:entered, "other", other_worker}
    args = %{"instance" => name, "id" => id}
    assert {:error, %{code: "not_found"}} = Ops.call("cancel", %{args | "instance" => other})
    assert {:error, %{code: "not_found"}} = Ops.call("cancel", %{args | "id" => "unknown"})
    assert {:ok, %{instance: ^name, id: ^id, status: "cancelled"}} = Ops.call("cancel", args)
    assert {:error, %{code: "already_finished"}} = Ops.call("cancel", args)

    for _ <- 1..2 do
      assert {:ok, %{status: "failed", error: %{code: "cancelled"}}} = Ops.call("result", args)
    end

    assert {:ok, :pending} = GenAgentServer.result(other, other_id)
    send(other_worker, :finish)

    assert eventually(fn ->
             match?({:ok, :completed, _}, GenAgentServer.result(other, other_id))
           end)

    assert {:error, %{code: "already_finished"}} =
             Ops.call("cancel", %{"instance" => other, "id" => other_id})

    assert {:error, %{code: "instance_not_found"}} =
             Ops.call("cancel", %{args | "instance" => "missing"})
  end

  test "remote CLI and stdio MCP use the canonical operation", %{names: [name, _], client: client} do
    for surface <- [:remote, :mcp, :ops_cli] do
      assert {:ok, id} = GenAgentServer.invoke(name, "worker", "blocked")
      assert_receive {:entered, "blocked", _}
      args = %{"instance" => name, "id" => id}

      case surface do
        :remote ->
          output =
            capture_io(fn ->
              Code.eval_string(Remote.expression(["--instance", name, "cancel", id]))
            end)

          assert {:ok, json} = Remote.decode_response(output)

          assert %{"instance" => ^name, "id" => ^id, "status" => "cancelled"} =
                   Jason.decode!(json)

          output =
            capture_io(fn ->
              Code.eval_string(Remote.expression(["--instance", name, "cancel", id]))
            end)

          assert {:error, message} = Remote.decode_response(output)
          assert message =~ "already_finished"

        :mcp ->
          assert {:ok,
                  %{
                    "structuredContent" => %{
                      "instance" => ^name,
                      "id" => ^id,
                      "status" => "cancelled"
                    }
                  }} = Snodo.Client.call_tool(client, "cancel", args)

        :ops_cli ->
          output =
            capture_io(fn ->
              Mix.Tasks.GenAgentServer.Ops.run(["cancel", "--instance", name, "--id", id])
            end)

          assert %{"instance" => ^name, "id" => ^id, "status" => "cancelled"} =
                   Jason.decode!(output)
      end

      assert {:error, %{code: "already_finished"}} = Ops.call("cancel", args)
    end

    output = capture_io(fn -> Code.eval_string(Remote.expression(["cancel", "unknown"])) end)
    assert {:error, message} = Remote.decode_response(output)
    assert message =~ "usage"
  end

  test "Ensemble controls remain responsive while a child cancellation is stalled", %{
    names: [name, _]
  } do
    assert {:ok, id} = GenAgentServer.invoke(name, "worker", "stalled")
    assert_receive {:entered, "stalled", _}
    child = GenAgent.whereis(GenAgentEnsemble.member_name(name, "worker"))
    :ok = :sys.suspend(child)
    cancel = Task.async(fn -> Ops.call("cancel", %{"instance" => name, "id" => id}) end)

    try do
      # Wait until the child receives the cancellation request before probing controls.
      assert eventually(fn ->
               {:messages, messages} = Process.info(child, :messages)

               Enum.any?(messages, fn
                 {:"$gen_call", _, {:cancel_request, _, _}} -> true
                 {:"$gen_call", _, {:cancel_request, _}} -> true
                 _ -> false
               end)
             end)

      status = Task.async(fn -> GenAgentEnsemble.status(name) end)
      assert {:ok, {:ok, _}} = Task.yield(status, 250) || Task.shutdown(status, :brutal_kill)
    after
      :ok = :sys.resume(child)
      assert {:ok, %{status: "cancelled"}} = Task.await(cancel, 6000)
    end
  end

  defp eventually(fun, n \\ 100)
  defp eventually(fun, 0), do: fun.()

  defp eventually(fun, n),
    do:
      fun.() or
        (
          Process.sleep(10)
          eventually(fun, n - 1)
        )
end

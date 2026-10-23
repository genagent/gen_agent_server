defmodule OperatorView.ReaderTest do
  use ExUnit.Case, async: true

  alias OperatorView.Reader

  defmodule StaticTransport do
    @moduledoc false
    @behaviour OperatorView.Transport

    # Runs in the calling test process: replies come from its dictionary.
    @impl true
    def call(operation, args, _timeout_ms) do
      send(self(), {:called, operation, args})
      Process.get(:reply).(operation, args)
    end
  end

  defp reply(data), do: Process.put(:reply, fn _operation, _args -> {:ok, data} end)

  test "scoped reads always name the instance and summaries always use limit 50" do
    reply(%{"invocations" => []})
    assert {:ok, []} = Reader.invocations(StaticTransport, "alpha", 100)
    assert_received {:called, "invocations", %{"instance" => "alpha", "limit" => 50}}

    reply(%{})
    assert {:ok, _description} = Reader.describe(StaticTransport, "alpha", 100)
    assert_received {:called, "describe_instance", %{"instance" => "alpha"}}
    assert {:ok, _status} = Reader.status(StaticTransport, "alpha", 100)
    assert_received {:called, "status", %{"instance" => "alpha"}}

    assert Reader.operations() == ~w(instances describe_instance status invocations)
  end

  test "describe keeps unknown and unset route settings distinct" do
    reply(%{
      "configured" => true,
      "strategy" => "GenAgentEnsemble.Strategies.Switchboard",
      "limits" => %{"max_in_flight" => 4},
      "routes" => [
        %{"name" => "review", "provider" => "codex", "model" => nil, "codex_sandbox" => nil},
        %{"name" => "smoke", "provider" => "echo"},
        "not a route"
      ]
    })

    assert {:ok, description} = Reader.describe(StaticTransport, "alpha", 100)
    assert description.configured == true
    assert description.max_in_flight == 4
    assert description.max_results == :unknown
    [review, smoke, malformed] = description.routes
    assert %{name: "review", provider: "codex", model: :not_set, access: :not_set} = review
    assert %{name: "smoke", provider: "echo", model: :unknown, access: :unknown} = smoke
    assert malformed.name == :unknown

    reply(%{"configured" => false, "routes" => [%{"name" => "worker"}]})

    assert {:ok, %{configured: false, strategy: :unknown, routes: [raw]}} =
             Reader.describe(StaticTransport, "alpha", 100)

    assert raw.provider == :unknown
  end

  test "status interprets only common fields and lists other fields by name" do
    reply(%{"strategy" => "S", "in_flight" => %{"t1" => "x"}, "queue" => [1, 2], 7 => true})

    assert {:ok, status} = Reader.status(StaticTransport, "alpha", 100)
    assert status.in_flight == 1
    assert status.pending == :unknown
    assert status.routes == :unknown
    assert status.other_fields == ["queue"]
  end

  test "summaries keep only fixed statuses, sources and error categories" do
    entries = [
      %{"id" => "a", "status" => "exploded", "source" => "elsewhere", "error_category" => "raw"},
      %{"id" => "b", "status" => "failed", "source" => "mcp", "error_category" => "timeout"}
    ]

    reply(%{"invocations" => entries})
    assert {:ok, [odd, failed]} = Reader.invocations(StaticTransport, "alpha", 100)
    assert %{status: :unknown, source: :unknown, error_category: :unknown} = odd
    assert %{status: "failed", source: "mcp", error_category: "timeout"} = failed
    assert odd.duration_ms == nil and odd.admitted_at_unix_ms == nil

    many = for n <- 1..60, do: %{"id" => "inv-#{n}", "status" => "completed"}
    reply(%{"invocations" => many})
    assert {:ok, summaries} = Reader.invocations(StaticTransport, "alpha", 100)
    assert length(summaries) == 50

    reply(%{"invocations" => ["not a summary"]})
    assert {:error, :bad_output} = Reader.invocations(StaticTransport, "alpha", 100)
  end

  test "errors are reduced to fixed codes" do
    for {error, code} <- [
          {%{"code" => "instance_not_found", "message" => "x"}, :instance_not_found},
          {%{code: "rpc_timeout", message: "x"}, :timeout},
          {%{code: "rpc_failed", message: "/path/bin exited 1"}, :release_unavailable},
          {%{code: "rpc_bad_output", message: "x"}, :bad_output},
          {%{"code" => "invalid_args", "message" => "x"}, :read_failed}
        ] do
      Process.put(:reply, fn _operation, _args -> {:error, error} end)
      assert {:error, ^code} = Reader.instances(StaticTransport, ["alpha"], 100)
    end

    Process.put(:reply, fn _operation, _args -> exit(:noproc) end)
    assert {:error, :read_failed} = Reader.instances(StaticTransport, ["alpha"], 100)

    reply(%{"instances" => ["ok", 7]})
    assert {:error, :bad_output} = Reader.instances(StaticTransport, ["alpha"], 100)
  end

  test "allowlisted instances listed after many others are still found" do
    others = for n <- 1..64, do: "a-#{String.pad_leading(Integer.to_string(n), 3, "0")}"
    reply(%{"instances" => others ++ ["server/default"]})

    allowed = ["server/default", "beta"]
    assert {:ok, running} = Reader.instances(StaticTransport, allowed, 100)
    assert running == ["server/default"]
    assert_received {:called, "instances", %{}}

    section = %{data: running, read_at: 1, error: nil, stale: false}

    assert OperatorView.Observation.instance_states(allowed, section) == [
             {"server/default", :running},
             {"beta", :not_running}
           ]
  end
end

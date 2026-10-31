defmodule GenAgentServerBackendErrorsTest do
  # Structured backend failures (`GenAgent.Backend.Error`) retain provider bodies,
  # headers, and message text. Public presentation must report only a coarse
  # category. The struct is built as a tagged map so these tests do not depend on
  # the installed core defining the module.
  use ExUnit.Case, async: false

  @moduletag :capture_log

  alias GenAgentServer.{Ops, Run}

  @sentinels [
    "SENTINEL_RAW_BODY",
    "SENTINEL_RAW_HEADER",
    "SENTINEL_MESSAGE",
    "SENTINEL_RETRY_AFTER",
    "SENTINEL_KIND",
    "sentinel_kind",
    "987654321"
  ]

  defmodule FailingBackend do
    @behaviour GenAgent.Backend
    def start_session(opts), do: {:ok, opts[:reason]}
    def prompt(reason, _prompt), do: {:error, reason}
    def update_session(session, _), do: session
    def terminate_session(_), do: :ok
  end

  defp typed(overrides \\ %{}) do
    Map.merge(
      %{
        __struct__: GenAgent.Backend.Error,
        provider: :anthropic,
        kind: :rate_limited,
        retryable?: true,
        status: 987_654_321,
        retry_after: "SENTINEL_RETRY_AFTER",
        message: "SENTINEL_MESSAGE",
        raw: %{
          body: %{"error" => %{"message" => "SENTINEL_RAW_BODY"}},
          headers: %{"authorization" => "SENTINEL_RAW_HEADER"}
        }
      },
      Map.new(overrides)
    )
  end

  defp refute_leak(term) do
    text = inspect(term, limit: :infinity, printable_limit: :infinity)

    for sentinel <- @sentinels do
      refute text =~ sentinel, "#{sentinel} leaked into #{text}"
    end

    term
  end

  defp nest(term, levels), do: Enum.reduce(1..levels, term, fn _, acc -> {:wrap, acc} end)

  defp override_echo(reason) do
    previous = Application.get_env(:gen_agent_server, :provider_overrides)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:gen_agent_server, :provider_overrides, previous),
        else: Application.delete_env(:gen_agent_server, :provider_overrides)
    end)

    Application.put_env(:gen_agent_server, :provider_overrides, %{
      "echo" => [backend: FailingBackend, reason: reason]
    })
  end

  defp instance(reason) do
    name = "backend-errors-#{System.unique_integer([:positive])}"

    agents = [
      {"worker", GenAgentEnsemble.Agents.Simple, [backend: FailingBackend, reason: reason]}
    ]

    assert {:ok, _} = GenAgentServer.start_instance(name, agents, poll_interval_ms: 60_000)
    on_exit(fn -> GenAgentServer.stop_instance(name) end)
    name
  end

  defp eventually(fun, attempts \\ 200) do
    cond do
      fun.() -> true
      attempts == 0 -> false
      true -> Process.sleep(10) && eventually(fun, attempts - 1)
    end
  end

  describe "direct normalization of typed errors" do
    test "reports the coarse kind and retryability only" do
      assert %{code: "backend_error", message: "backend_error: rate_limited (retryable)"} =
               refute_leak(Ops.normalize(typed()))

      assert %{code: "backend_error", message: "backend_error: authentication"} =
               refute_leak(Ops.normalize(typed(%{kind: :authentication, retryable?: false})))
    end

    test "every allowlisted kind is preserved" do
      kinds =
        ~w(rate_limited authentication invalid_request server_error http_error transport
           provider_error conversation_lost invalid_response timeout)a

      for kind <- kinds do
        expected = "backend_error: #{kind}"

        assert %{code: "backend_error", message: ^expected} =
                 refute_leak(Ops.normalize(typed(%{kind: kind, retryable?: false})))
      end
    end

    test "unknown or malformed kinds use the fixed fallback" do
      for kind <- [:sentinel_kind_atom, "SENTINEL_KIND_STRING", nil, 7, {:sentinel_kind, 1}] do
        assert %{code: "backend_error", message: "backend_error: unclassified (retryable)"} =
                 refute_leak(Ops.normalize(typed(%{kind: kind})))
      end

      missing = typed() |> Map.delete(:kind) |> Map.delete(:retryable?)

      assert %{code: "backend_error", message: "backend_error: unclassified"} =
               refute_leak(Ops.normalize(missing))

      # Only a literal `true` is reported as retryable.
      for retryable <- ["SENTINEL_KIND", :true_ish, 1, nil] do
        assert %{message: "backend_error: rate_limited"} =
                 refute_leak(Ops.normalize(typed(%{retryable?: retryable})))
      end
    end

    test "the result is JSON-safe" do
      assert {:ok, json} = typed() |> Ops.normalize() |> Jason.encode()
      refute_leak(json)
    end
  end

  describe "nested framework reasons" do
    test "stage tuples and atom wrappers do not expose the typed error" do
      assert %{code: "stage_one", message: message} =
               refute_leak(Ops.normalize({:stage_one, typed()}))

      assert message =~ "rate_limited"

      assert %{code: "stage_down", message: message} =
               refute_leak(Ops.normalize({:stage_down, {:stage_one, typed()}}))

      assert message =~ "rate_limited"

      assert %{code: "agent_down", message: message} =
               refute_leak(Ops.normalize({:agent_down, {"stage-one", typed(%{kind: :other})}}))

      assert message =~ "unclassified"
    end

    test "binary stage names, lists, maps and larger tuples are covered" do
      for reason <- [
            {"stage one", typed()},
            {:a, :b, typed()},
            [typed()],
            [{:stage, typed()} | typed()],
            %{stage: "one", error: typed()},
            %{typed() => :key},
            {:worker_down, %{reason: [typed(), {:nested, typed()}]}}
          ] do
        assert %{code: _, message: message} = refute_leak(Ops.normalize(reason))
        assert message =~ "backend_error"
      end
    end

    test "wrappers around other structs are redacted without being called" do
      wrapper = {:stage, %{__struct__: SentinelUnloadedStruct, error: typed()}}
      assert %{code: "stage"} = refute_leak(Ops.normalize(wrapper))
    end
  end

  describe "bounded redaction" do
    test "deep wrappers fail closed past the depth limit" do
      assert %{code: "wrap", message: message} =
               refute_leak(Ops.normalize(nest(typed(), 100)))

      assert message =~ "<redacted>"

      assert %{code: "wrap", message: message} =
               refute_leak(Ops.normalize(nest(typed(), 10)))

      assert message =~ "{:backend_error, :rate_limited}"
      refute message =~ "<redacted>"
    end

    test "long lists keep early typed errors redacted and drop the unexamined tail" do
      assert %{message: early} =
               refute_leak(Ops.normalize({:stage, [typed() | List.duplicate(:filler, 5_000)]}))

      assert early =~ "{:backend_error, :rate_limited}"

      assert %{code: "stage"} =
               refute_leak(Ops.normalize({:stage, List.duplicate(:filler, 5_000) ++ [typed()]}))

      assert %{code: "stage"} =
               refute_leak(Ops.normalize({:stage, for(_ <- 1..2_000, do: [typed()])}))
    end

    test "wide maps and tuples are replaced whole" do
      wide_map = Map.new(1..5_000, &{&1, typed()})
      wide_tuple = List.to_tuple(List.duplicate(typed(), 5_000))

      for container <- [wide_map, wide_tuple] do
        assert %{code: "stage", message: ~s(stage: "<redacted>")} =
                 refute_leak(Ops.normalize({:stage, container}))
      end

      assert %{code: "error", message: ~s("<redacted>")} = Ops.normalize(wide_map)
    end

    test "a typed root discards raw without reading it" do
      huge = List.duplicate(%{"SENTINEL_RAW_BODY" => nest(typed(), 100)}, 100_000)

      assert %{code: "backend_error", message: "backend_error: rate_limited (retryable)"} =
               refute_leak(Ops.normalize(typed(%{raw: huge, message: huge})))

      assert "backend_error: rate_limited (retryable)" ==
               Ops.error_text(typed(%{raw: huge, message: huge}))
    end

    test "ordinary terms within the limits are unchanged" do
      detail = [{:a, 1}, %{k: "v"}, {:nested, {:deeper, [1, 2, 3]}}, List.duplicate(:x, 40)]

      assert Ops.normalize({:stage, detail}) ==
               %{code: "stage", message: "stage: " <> inspect(detail, printable_limit: 500)}

      assert Ops.error_text({:stage, detail}) == inspect({:stage, detail})
    end
  end

  describe "error_text" do
    test "typed errors become their category and legacy reasons keep inspect text" do
      assert Ops.error_text(typed()) == "backend_error: rate_limited (retryable)"

      assert Ops.error_text(typed(%{kind: :sentinel_kind_atom})) ==
               "backend_error: unclassified (retryable)"

      refute_leak(Ops.error_text({:stage, typed()}))
      assert Ops.error_text({:stage, typed()}) =~ "{:backend_error, :rate_limited}"

      for reason <- [:timeout, :not_found, {:unknown_agent, "x"}, [1, 2], %{a: 1}, "text"] do
        assert Ops.error_text(reason) == inspect(reason)
      end
    end
  end

  describe "Run and run_pattern" do
    @solo %{"pattern" => "solo", "agent" => %{"provider" => "echo"}}

    test "failed items carry the coarse category, not the typed error" do
      override_echo(typed())

      assert {:ok, %{results: [item]} = report} = Run.run(@solo, ["p"], timeout: 10_000)
      assert item.status == :failed
      assert item.error == "backend_error: rate_limited (retryable)"
      refute_leak(report)
      assert {:ok, _} = Jason.encode(report)

      assert {:ok, public} = Ops.call("run_pattern", %{"spec" => @solo, "prompts" => ["p"]})

      assert [%{"status" => "failed", "error" => "backend_error: rate_limited (retryable)"}] =
               public["results"]

      refute_leak(public)
    end

    test "pipeline stage wrappers do not expose the typed error" do
      override_echo(typed())
      spec = %{"pattern" => "pipeline", "stages" => [@solo["agent"], @solo["agent"]]}

      assert {:ok, %{results: [item]} = report} = Run.run(spec, ["p"], timeout: 10_000)
      assert item.status == :failed
      assert item.error =~ "{:backend_error, :rate_limited}"
      refute_leak(report)

      assert {:ok, public} = Ops.call("run_pattern", %{"spec" => spec, "prompts" => ["p"]})
      refute_leak(public)
    end

    test "oversized wrappers are truncated instead of inspected" do
      override_echo({:stage, List.duplicate(:filler, 5_000) ++ [typed()]})

      assert {:ok, %{results: [item]} = report} = Run.run(@solo, ["p"], timeout: 10_000)
      assert item.status == :failed
      refute_leak(report)
    end

    test "legacy reasons keep their inspect text" do
      reason = {:private_error, "legacy reason"}
      override_echo(reason)

      assert {:ok, %{results: [item]}} = Run.run(@solo, ["p"], timeout: 10_000)
      assert item.status == :failed
      assert item.error == inspect(reason)
    end
  end

  describe "CLI errors" do
    test "local and remote CLI presentation omits typed diagnostics" do
      for reason <- [typed(), {"stage", typed()}] do
        message = GenAgentServer.CLI.error_message(["ask", "echo", "p"], reason)
        assert message =~ "rate_limited"
        refute_leak(message)
      end

      reason = {:legacy_failure, "legacy detail"}

      assert GenAgentServer.CLI.error_message([], reason) ==
               "GenAgent request failed: #{inspect(reason)}"
    end
  end

  describe "legacy reasons are unchanged" do
    test "atoms, config errors, tagged tuples and arbitrary terms" do
      assert Ops.normalize(:timeout) == %{code: "timeout", message: "timeout"}
      assert Ops.normalize(:cancelled) == %{code: "cancelled", message: "cancelled"}

      assert Ops.normalize({:invalid_config, "bad route"}) ==
               %{code: "invalid_config", message: "bad route"}

      assert Ops.normalize({:http_error, 429, "slow down"}) ==
               %{code: "error", message: ~s({:http_error, 429, "slow down"})}

      assert Ops.normalize({:private_error, "reason"}) ==
               %{code: "private_error", message: ~s(private_error: "reason")}

      assert Ops.normalize({:stage, {:timeout, 5}}) ==
               %{code: "stage", message: "stage: {:timeout, 5}"}

      assert Ops.normalize({"stage", :boom}) == %{code: "error", message: ~s({"stage", :boom})}

      assert Ops.normalize(%{message: "legacy"}) ==
               %{code: "error", message: ~s(%{message: "legacy"})}

      assert Ops.normalize([1, 2, 3]) == %{code: "error", message: "[1, 2, 3]"}
    end

    test "other structs keep their existing presentation" do
      reason = {:stage, %ArgumentError{message: "legacy detail"}}
      assert Ops.normalize(reason).message =~ "legacy detail"
    end
  end

  describe "jsonable" do
    test "a typed error in a document becomes its coarse category" do
      data = Ops.jsonable(%{error: typed(), stages: [{:one, typed(%{kind: :timeout})}]})

      assert data == %{
               "error" => "backend_error: rate_limited (retryable)",
               "stages" => [["one", "backend_error: timeout (retryable)"]]
             }

      refute_leak(data)
    end
  end

  describe "failed invocations through the public operations" do
    test "ask and result present a coarse category while Elixir keeps the original" do
      reason = typed()
      name = instance(reason)

      ask = %{"instance" => name, "agent" => "worker", "prompt" => "p"}
      expected = %{code: "backend_error", message: "backend_error: rate_limited (retryable)"}

      assert {:error, ^expected} = error = Ops.call("ask", ask)
      refute_leak(error)

      assert {:ok, id} = GenAgentServer.invoke(name, "worker", "q")

      assert eventually(fn ->
               match?({:ok, :failed, _}, GenAgentServer.result(name, id))
             end)

      assert {:ok, %{id: ^id, status: "failed", error: public}} =
               result = Ops.call("result", %{"instance" => name, "id" => id})

      assert public == expected
      refute_leak(result)
      assert {:ok, _} = result |> elem(1) |> Jason.encode()

      # Direct Elixir callers can still handle the original diagnostics.
      assert {:ok, :failed, ^reason} = GenAgentServer.result(name, id)
      assert reason.raw.body["error"]["message"] == "SENTINEL_RAW_BODY"
      assert {:error, ^reason} = GenAgentServer.ask_instance(name, "worker", "r", [])
    end

    test "nested stage failures and unknown kinds stay redacted" do
      for reason <- [{:stage_one, typed()}, typed(%{kind: :sentinel_kind_atom})] do
        name = instance(reason)

        ask = %{"instance" => name, "agent" => "worker", "prompt" => "p"}
        assert {:error, %{code: code, message: message}} = error = Ops.call("ask", ask)

        refute_leak(error)
        assert code in ["stage_one", "backend_error"]
        assert message =~ "backend_error" or message =~ "rate_limited"
      end
    end

    test "legacy backend failures keep their previous result" do
      name = instance({:private_error, "legacy reason"})

      assert {:error, %{code: "private_error", message: ~s(private_error: "legacy reason")}} =
               Ops.call("ask", %{"instance" => name, "agent" => "worker", "prompt" => "p"})
    end
  end
end

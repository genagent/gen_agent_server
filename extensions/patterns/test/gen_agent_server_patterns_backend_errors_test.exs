defmodule GenAgentServerPatternsBackendErrorsTest do
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
end

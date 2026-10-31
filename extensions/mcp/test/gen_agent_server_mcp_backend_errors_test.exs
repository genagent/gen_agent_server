defmodule GenAgentServerMCPBackendErrorsTest do
  # Structured backend failures (`GenAgent.Backend.Error`) retain provider bodies,
  # headers, and message text. Public presentation must report only a coarse
  # category. The struct is built as a tagged map so these tests do not depend on
  # the installed core defining the module.
  use ExUnit.Case, async: false

  @moduletag :capture_log

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

  test "the MCP adapter reports the same coarse category" do
    name = instance(typed())

    assert {:ok, error} =
             GenAgentServer.MCP.run("ask", %{
               "instance" => name,
               "agent" => "worker",
               "prompt" => "p"
             })

    refute_leak(error)
    assert inspect(error) =~ "backend_error: rate_limited (retryable)"

    assert {:ok, id} = GenAgentServer.invoke(name, "worker", "q")

    assert eventually(fn ->
             match?({:ok, :failed, _}, GenAgentServer.result(name, id))
           end)

    assert {:ok, result} = GenAgentServer.MCP.run("result", %{"instance" => name, "id" => id})
    refute_leak(result)
    assert inspect(result) =~ "backend_error: rate_limited (retryable)"
  end
end

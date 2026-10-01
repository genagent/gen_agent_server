defmodule GenAgentServer.Run do
  @moduledoc """
  Runs an Ensemble pattern described by a `GenAgentServer.PatternSpec` spec in
  a temporary server instance and returns structured results.

  All prompts are submitted before any result is awaited, so a `pool` or
  `switchboard` spec processes them concurrently. The instance is stopped when
  the run finishes, including on timeout.
  """

  alias GenAgentServer.PatternSpec

  @poll_ms 50

  @type item :: %{
          prompt: String.t(),
          route: String.t(),
          id: String.t() | nil,
          status: :completed | :failed | :timeout | :rejected,
          text: String.t() | nil,
          error: String.t() | nil,
          usage: map() | nil,
          elapsed_ms: non_neg_integer()
        }

  @doc """
  Run `prompts` through the pattern in `spec`.

  Options:

    * `:cwd` -- default project directory for CLI providers.
    * `:to` -- route for every prompt (switchboard specs); defaults to the
      first route.
    * `:timeout` -- milliseconds to wait for all results (default 600_000).
    * `:instance` -- instance name (default: a unique `run/...` name).
  """
  @spec run(map(), [String.t()], keyword()) :: {:ok, map()} | {:error, term()}
  def run(spec, prompts, opts \\ []) when is_list(prompts) and prompts != [] do
    with {:ok, plan} <- PatternSpec.parse(spec, Keyword.take(opts, [:cwd])),
         {:ok, route} <- route(plan, Keyword.get(opts, :to)) do
      name =
        Keyword.get(opts, :instance, "run/#{plan.pattern}-#{System.unique_integer([:positive])}")

      timeout = Keyword.get(opts, :timeout, 600_000)

      case start(name, plan) do
        {:ok, _pid} ->
          try do
            started = now()
            items = Enum.map(prompts, &submit(name, route, &1, started))
            items = await(name, items, started, started + timeout)

            {:ok,
             %{
               pattern: plan.pattern,
               instance: name,
               routes: plan.routes,
               results: items,
               elapsed_ms: now() - started
             }}
          after
            GenAgentServer.stop_instance(name)
          end

        {:error, reason} ->
          {:error, {:start_failed, reason}}
      end
    end
  end

  defp route(%{routes: routes}, nil), do: {:ok, hd(routes)}

  defp route(%{routes: routes}, to) do
    if to in routes, do: {:ok, to}, else: {:error, {:unknown_route, to, routes}}
  end

  defp start(name, %{pattern: "switchboard"} = plan) do
    GenAgentServer.start_instance(name, plan.strategy_opts[:agents], max_in_flight: 64)
  end

  defp start(name, plan) do
    GenAgentServer.start_pattern_instance(
      name,
      hd(plan.routes),
      plan.strategy,
      plan.strategy_opts,
      max_in_flight: 64
    )
  end

  defp submit(name, route, prompt, started) do
    base = %{prompt: prompt, route: route, id: nil, text: nil, error: nil, usage: nil}

    case GenAgentServer.invoke(name, route, prompt, source: :api) do
      {:ok, id} ->
        Map.merge(base, %{id: id, status: :pending, elapsed_ms: 0})

      {:error, reason} ->
        Map.merge(base, %{status: :rejected, error: inspect(reason), elapsed_ms: now() - started})
    end
  end

  defp await(name, items, started, deadline) do
    items = Enum.map(items, &check(name, &1, started))

    cond do
      Enum.all?(items, &(&1.status != :pending)) ->
        items

      now() >= deadline ->
        Enum.map(items, fn
          %{status: :pending} = item -> %{item | status: :timeout}
          item -> item
        end)

      true ->
        Process.sleep(@poll_ms)
        await(name, items, started, deadline)
    end
  end

  defp check(name, %{status: :pending, id: id} = item, started) do
    case GenAgentServer.result(name, id) do
      {:ok, :pending} ->
        item

      {:ok, :completed, response} ->
        %{item | status: :completed, text: response.text, usage: Map.get(response, :usage)}
        |> stamp(started)

      {:ok, :failed, reason} ->
        %{item | status: :failed, error: inspect(reason)} |> stamp(started)

      {:error, reason} ->
        %{item | status: :failed, error: inspect(reason)} |> stamp(started)
    end
  end

  defp check(_name, item, _started), do: item

  # Elapsed time is measured by the caller's poll loop, so it is accurate to
  # about the poll interval.
  defp stamp(item, started), do: %{item | elapsed_ms: now() - started}

  defp now, do: System.monotonic_time(:millisecond)
end

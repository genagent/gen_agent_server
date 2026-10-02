# Run with: mix run examples/codex_parallel_review.exs PROJECT_DIR "Task one" "Task two" ["Task three" ["Task four"]]
# Echo deterministically splits two to four independent tasks. Read-only Codex
# workers run under a managed Supervisor and stop after their replies.

{cwd, review_tasks} =
  case System.argv() do
    [cwd, first, second | rest] when length(rest) <= 2 ->
      {Path.expand(cwd), [first, second | rest]}

    _ ->
      raise "usage: mix run examples/codex_parallel_review.exs PROJECT_DIR \"Task one\" \"Task two\" [\"Task three\" [\"Task four\"]]"
  end

unless File.dir?(cwd), do: raise("project directory does not exist: #{cwd}")
unless Enum.all?(review_tasks, &(&1 != "")), do: raise("review tasks must not be empty")

name = "parallel-review-#{System.unique_integer([:positive])}"
simple = GenAgentEnsemble.Agents.Simple
{:ok, codex_opts} = GenAgentServer.Providers.backend_opts("codex", cwd: cwd)

decomposer = fn text ->
  text
  |> String.replace_prefix("echo: ", "")
  |> Jason.decode!()
end

synthesizer = fn outputs ->
  Enum.map_join(outputs, "\n\n", fn {worker, text} -> "#{worker}:\n#{text}" end)
end

{:ok, _pid} =
  GenAgentServer.start_pattern_instance(
    name,
    "review",
    GenAgentEnsemble.Strategies.Supervisor,
    coordinator: {"splitter", simple, backend: GenAgentEnsemble.Backends.Echo},
    worker_template: {"codex", simple, codex_opts},
    decomposer: decomposer,
    synthesizer: synthesizer
  )

try do
  tasks =
    review_tasks
    |> Enum.map(&"#{&1}\n\nCite source locations. Do not edit files.")
    |> Jason.encode!()

  case GenAgentServer.ask_instance(name, "review", tasks) do
    {:ok, response} ->
      IO.puts(response.text)

      {:ok, %{agents: ["splitter"], in_flight: 0, pending_tokens: []}} =
        GenAgentServer.status(name)

    {:error, reason} ->
      raise "parallel review failed: #{inspect(reason)}"
  end
after
  GenAgentServer.stop_instance(name)
end

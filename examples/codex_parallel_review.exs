# Run with: mix run examples/codex_parallel_review.exs PROJECT_DIR "Task one" "Task two"
# Echo deterministically splits two independent tasks. Two read-only Codex
# workers run under a managed Supervisor and stop after their replies.

{cwd, first_task, second_task} =
  case System.argv() do
    [cwd, first, second] when first != "" and second != "" ->
      {Path.expand(cwd), first, second}

    _ ->
      raise "usage: mix run examples/codex_parallel_review.exs PROJECT_DIR \"Task one\" \"Task two\""
  end

unless File.dir?(cwd), do: raise("project directory does not exist: #{cwd}")

name = "parallel-review-#{System.unique_integer([:positive])}"
simple = GenAgentEnsemble.Agents.Simple

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
    worker_template:
      {"codex", simple,
       backend: GenAgent.Backends.Codex, cwd: cwd, sandbox: :read_only, approval_policy: :never},
    decomposer: decomposer,
    synthesizer: synthesizer
  )

try do
  tasks =
    [first_task, second_task]
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

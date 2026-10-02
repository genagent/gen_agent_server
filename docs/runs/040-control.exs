project = "/tmp/gen_agent_batch_02"
report_path = "/tmp/gen_agent_batch_02_report.json"
name = "batch02-#{System.unique_integer([:positive])}"

codex_spec = %{
  "pattern" => "pool",
  "worker_count" => 2,
  "codex_sandbox" => "read_only",
  "worker" => %{
    "provider" => "codex",
    "role" => "Verify one claimed issue against current source in this checkout. Read files and tests yourself. Do not edit, commit, or run project backends. Return VERDICT: CONFIRMED, REFUTED, or CHANGED on a line, followed by precise source locations, a minimal implementation contract, focused regression tests, and any overlapping open PR. Be specific about compatibility. Keep under 500 words."
  }
}

codex_tasks = [
  "Core issue #248, release compatibility slice: core release PR #313 proposes 0.7.0 while CLI adapters and Ensemble require core ~> 0.6.0, Anthropic/OpenAI list supported series only through 0.6, gen_agent_server requires ~> 0.6.1, and scripts/consumer-check.sh hardcodes current package lines. Verify current manifests/scripts and identify the smallest safe sequence to test 0.7.0, widen requirements, refresh consumer baseline, and release dependents. Do not edit; this is read-only triage.",
  "Ensemble issue #173: Supervisor synthesizer currently sees worker names and texts but not the assigned subtask. Verify against latest extensions/ensemble code and tests. Design the smallest backward-compatible way to expose subtasks to custom synthesizers and label default sections. Include ordering, zero-worker case, and focused tests. Do not edit; this is read-only triage."
]

claude_spec = %{
  "pattern" => "solo",
  "claude_permission_mode" => "plan",
  "agent" => %{
    "provider" => "claude",
    "model" => "opus",
    "role" => "Design the contract for one risky core issue after independently reading current source and tests. Do not edit or run project backends. Return a concise verdict, exact affected functions, externally visible semantics for ask, tell/poll, and completion recipients, cancellation/interrupt/timeout behavior, telemetry/ref handling, and deterministic regression cases. Distinguish decisions needing design from simple edits. Keep under 750 words."
  }
}

claude_task = "Core issue #242: handle_error/3 returning {:prompt, retry, state} currently records the first error to the original caller and sends the retried success through an unobservable self_chain ref. Verify on current main and design an end-to-end result contract that delivers the final attempt to the original ask, tell/poll, and completion recipient. Preserve existing self-chain behavior for independent follow-ups. Consider repeated retries, halt, caller cancellation, interrupt, watchdog, supervisor failure, and queued requests. This is read-only design, not implementation."

{:ok, supervisor} = Task.Supervisor.start_link()

jobs = [
  {:codex, "#{name}/codex", fn ->
    GenAgentServer.Run.run(codex_spec, codex_tasks,
      cwd: project, timeout: 900_000, instance: "#{name}/codex")
  end},
  {:claude, "#{name}/claude", fn ->
    GenAgentServer.Run.run(claude_spec, [claude_task],
      cwd: project, timeout: 900_000, instance: "#{name}/claude")
  end}
]

tasks = Enum.map(jobs, fn {label, instance, fun} ->
  {label, instance, Task.Supervisor.async_nolink(supervisor, fun)}
end)

try do
  yielded = Task.yield_many(Enum.map(tasks, &elem(&1, 2)), 960_000)

  results = Enum.zip_with(tasks, yielded, fn {label, instance, task}, {_task, reply} ->
    outcome =
      case reply do
        {:ok, {:ok, report}} ->
          %{status: "completed", elapsed_ms: report.elapsed_ms,
            items: Enum.map(report.results, fn item ->
              %{status: to_string(item.status), prompt: item.prompt,
                text: item.text, error: item.error,
                elapsed_ms: item.elapsed_ms, usage: item.usage}
            end)}
        {:ok, {:error, reason}} -> %{status: "start_failed", error: inspect(reason)}
        {:exit, reason} -> %{status: "crashed", error: inspect(reason)}
        nil -> %{status: "timeout", error: "caller wait expired"}
      end

    Map.merge(outcome, %{label: to_string(label), instance: instance,
      worker_pid: inspect(task.pid)})
  end)

  File.write!(report_path, Jason.encode!(%{project: project, jobs: results}, pretty: true))
  Enum.each(results, fn result ->
    IO.puts("#{result.label}: #{result.status} #{length(Map.get(result, :items, []))} items")
  end)
  IO.puts("report: #{report_path}")
after
  Enum.each(tasks, fn {_label, instance, task} ->
    if Process.alive?(task.pid), do: Task.shutdown(task, :brutal_kill)
    GenAgentServer.stop_instance(instance)
  end)
  Supervisor.stop(supervisor)
end

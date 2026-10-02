project = "/tmp/gen_agent_issue_106"
out = "/tmp/gen_agent_issue_106_design.json"
name = "issue106-design-#{System.unique_integer([:positive])}"

spec = %{
  "pattern" => "solo",
  "claude_permission_mode" => "plan",
  "agent" => %{
    "provider" => "claude",
    "model" => "opus",
    "role" => "Read-only API designer. Verify the current source and tests, and design the smallest additive request-ref-correlated stream delivery API. Do not edit, commit, or run network commands. Address queued requests, early deltas, completion ordering, cancellation, callback compatibility, recipient death, and deterministic tests. Separate core scope from Ensemble follow-up. Keep under 1500 words."
  }
}

prompt = File.read!("/tmp/gen_agent_issue_106.md") <> "\n\nDesign a concrete implementation for current main. In particular choose whether stream_to on tell_with_completion, a callback arity, or telemetry is the safest first slice, and explain why. Cite current file and line references. Do not edit."

try do
  case GenAgentServer.Run.run(spec, [prompt], cwd: project, timeout: 900_000, instance: name) do
    {:ok, report} ->
      File.write!(out, Jason.encode!(%{instance: name, spec: spec, prompt: prompt,
        elapsed_ms: report.elapsed_ms, results: Enum.map(report.results, fn item ->
          %{status: to_string(item.status), text: item.text, error: item.error,
            elapsed_ms: item.elapsed_ms, usage: item.usage}
        end)}, pretty: true))
      IO.puts("report: #{out}")
    {:error, reason} -> raise "server run failed: #{inspect(reason)}"
  end
after
  GenAgentServer.stop_instance(name)
end

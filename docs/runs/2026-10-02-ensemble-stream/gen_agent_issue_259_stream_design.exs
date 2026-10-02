project = "/tmp/gen_agent_issue_259_stream"
out = "/tmp/gen_agent_issue_259_stream_design.json"
name = "issue259-stream-design-#{System.unique_integer([:positive])}"

spec = %{
  "pattern" => "solo",
  "claude_permission_mode" => "plan",
  "agent" => %{
    "provider" => "claude",
    "model" => "opus",
    "role" => "Read-only Ensemble API designer. Recheck the current core and Ensemble sources. Design the smallest additive token-correlated stream forwarding layer for the existing tell_with_completion and cancellation contracts. No edits, commits, network commands, or backend calls. Analyze multi-worker patterns, early child events before ref registration, token completion, cancellation fences, halted agents, recipient death, ordering, and deterministic tests. Keep implementation scope within Ensemble unless a demonstrated core gap remains."
  }
}

prompt = File.read!("/tmp/gen_agent_issue_259_stream.md") <> "\n\nThe first two slices of this issue shipped as Ensemble 0.6.0. Core PR #341 is merged on this checkout: tell_with_completion/5 now supports stream_to: pid and emits {:gen_agent, :event, name, ref, event} before completion for a shared recipient. Design the remaining Ensemble token-level forwarding slice. Specify public API and message shape, where recipients live, exact mapping from child ref to token/member, how to subscribe only opted-in work, and how to fence late events after completion or cancel. Identify deterministic tests against current code. Do not edit."

try do
  case GenAgentServer.Run.run(spec, [prompt], cwd: project, timeout: 900_000, instance: name) do
    {:ok, report} ->
      File.write!(out, Jason.encode!(%{instance: name, spec: spec, prompt: prompt,
        elapsed_ms: report.elapsed_ms, results: Enum.map(report.results, fn item ->
          %{id: item.id, status: to_string(item.status), text: item.text, error: item.error,
            elapsed_ms: item.elapsed_ms, usage: item.usage}
        end)}, pretty: true))
      IO.puts("report: #{out}")
    {:error, reason} -> raise "server run failed: #{inspect(reason)}"
  end
after
  GenAgentServer.stop_instance(name)
end

project = "/tmp/gen_agent_issue_259"
out = "/tmp/gen_agent_issue_259_design.json"
name = "issue259-design-#{System.unique_integer([:positive])}"

spec = %{
  "pattern" => "solo",
  "claude_permission_mode" => "plan",
  "agent" => %{
    "provider" => "claude",
    "model" => "opus",
    "role" => "Design an additive Ensemble token API after reading current source and tests. Do not edit, commit, or run project backends. Recheck the issue claims. Specify exact API messages and return values, ownership and late-event behavior, cancellation of one token without stopping the session, strategy interaction, stream forwarding, compatibility, and deterministic tests. Distinguish changes feasible in one PR from follow-up work. Keep under 1200 words."
  }
}

prompt = "Issue genagent/gen_agent#259: Ensemble tell results currently require destructive poll/inbox, no completion notification, no token cancellation, and no forwarded subagent stream events. The IEx await helper polls every 50 ms. Design the smallest coherent additive API akin to core tell_with_completion/4, cancellation, and stream forwarding. Read extensions/ensemble/lib and relevant core APIs/tests yourself. Check interactions with ask, multi-worker patterns, stale refs, and completed tokens. Do not edit."

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

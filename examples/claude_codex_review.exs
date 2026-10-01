# Run with: mix run examples/claude_codex_review.exs PROJECT_DIR "Review task"
# Codex drafts a read-only review; Claude checks its claims against the same
# project. The Pipeline returns Claude's final response.

{cwd, task} =
  case System.argv() do
    [cwd, task] when task != "" -> {Path.expand(cwd), task}
    _ -> raise "usage: mix run examples/claude_codex_review.exs PROJECT_DIR \"Review task\""
  end

unless File.dir?(cwd), do: raise("project directory does not exist: #{cwd}")

name = "review-pipeline-#{System.unique_integer([:positive])}"
simple = GenAgentEnsemble.Agents.Simple

{:ok, _pid} =
  GenAgentServer.start_pattern_instance(
    name,
    "review",
    GenAgentEnsemble.Strategies.Pipeline,
    stages: [
      {"codex-draft", simple,
       backend: GenAgent.Backends.Codex, cwd: cwd, sandbox: :read_only, approval_policy: :never},
      {"claude-verify", simple,
       backend: GenAgent.Backends.Claude,
       cwd: cwd,
       permission_mode: :plan,
       system_prompt:
         "You are the verification stage in a code-review pipeline. The user text is the previous agent's draft. Check its concrete claims against files in the current repository. Do not edit files. Return VERIFIED or CORRECTED, followed by concise evidence and file locations. State clearly what you could not verify."}
    ]
  )

try do
  prompt =
    "#{task}\n\nReturn a concise draft with concrete claims and file locations. Do not edit files."

  case GenAgentServer.ask_instance(name, "review", prompt) do
    {:ok, response} -> IO.puts(response.text)
    {:error, reason} -> raise "review pipeline failed: #{inspect(reason)}"
  end
after
  GenAgentServer.stop_instance(name)
end

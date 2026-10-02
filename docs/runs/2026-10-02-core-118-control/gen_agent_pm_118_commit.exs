release = "/tmp/gen_agent_server_claude_023/_build/prod/rel/gen_agent_server/bin/gen_agent_server"
project = "/tmp/gen_agent_claude_options_117"
{:ok, client} = Snodo.Client.connect({:stdio, release, ["eval", "GenAgentServer.MCP.serve()"]}, timeout: 240_000)

call = fn name, args ->
  case Snodo.Client.call_tool(client, name, args, timeout: 240_000) do
    {:ok, %{"isError" => true} = response} -> raise "#{name}: #{inspect(response)}"
    {:ok, %{"structuredContent" => value}} -> value
    other -> raise "#{name}: #{inspect(other)}"
  end
end

try do
  config = %{
    "cwd" => project,
    "routes" => [%{"name" => "commit", "provider" => "codex", "model" => "gpt-6-luna", "effort" => "low", "codex_sandbox" => "workspace_write"}]
  }
  call.("create_instance", %{"instance" => "pm-core-118-commit", "config" => config})

  prompt = "The existing six-file integrations/claude diff for issue #118 passed tests and final review. Commit only that diff, with no source edits. First run git status --short and git diff --check; abort if unrelated modified files exist. Stage exactly the six modified integrations/claude files and commit with message 'fix(claude): preserve CLI result text and errors'. Report commit SHA and git status. Do not push, fetch, or rebase yet. If your sandbox denies writing .git, report that mechanical control gap and stop rather than retrying around it."

  result = call.("ask", %{"instance" => "pm-core-118-commit", "agent" => "commit", "prompt" => prompt, "timeout_ms" => 180_000})
  IO.puts(result["text"] || inspect(result))
  IO.inspect(Map.take(result, ["status", "session_id"]), label: "metadata")
after
  Snodo.Client.close(client)
end

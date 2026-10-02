release = "/tmp/gen_agent_server_claude_023/_build/prod/rel/gen_agent_server/bin/gen_agent_server"
project = "/tmp/gen_agent_claude_options_117"
{:ok, client} = Snodo.Client.connect({:stdio, release, ["eval", "GenAgentServer.MCP.serve()"]}, timeout: 180_000)

call = fn name, args ->
  case Snodo.Client.call_tool(client, name, args, timeout: 180_000) do
    {:ok, %{"isError" => true} = response} -> raise "#{name}: #{inspect(response)}"
    {:ok, %{"structuredContent" => value}} -> value
    other -> raise "#{name}: #{inspect(other)}"
  end
end

try do
  config = %{
    "cwd" => project,
    "routes" => [%{"name" => "inspect", "provider" => "codex", "model" => "gpt-6-luna", "effort" => "low"}]
  }

  IO.inspect(call.("create_instance", %{"instance" => "pm-core-baseline", "config" => config}), label: "created")

  prompt = "Read-only baseline for the GenAgent core maintenance handoff. Inspect this checkout's git branch/status, relevant changed files, and last commit. Identify whether issue #118 work is locally complete, what exact changes remain uncommitted, and whether any tests/checks are documented. Check GitHub issue #118 and open PRs for overlap using gh only if available; if network or gh is unavailable, say so explicitly. Recommend the next bounded fix from this checkout. Do not edit files, commit, push, or create issues/PRs. Be concise and cite paths/commands/results."

  result = call.("ask", %{"instance" => "pm-core-baseline", "agent" => "inspect", "prompt" => prompt, "timeout_ms" => 150_000})
  IO.puts(result["text"] || inspect(result))
  IO.inspect(Map.take(result, ["status", "session_id"]), label: "metadata")
after
  Snodo.Client.close(client)
end

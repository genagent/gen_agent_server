release = "/tmp/gen_agent_server_claude_023/_build/prod/rel/gen_agent_server/bin/gen_agent_server"
project = "/tmp/gen_agent_server_claude_023"
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
    "routes" => [%{"name" => "inspect", "provider" => "codex", "model" => "gpt-6-luna", "effort" => "low"}]
  }
  call.("create_instance", %{"instance" => "pm-server-81-inspect", "config" => config})

  prompt = "Read-only PM scoping for genagent/gen_agent_server issue #81. Use gh issue view 81 and gh pr list if GitHub is reachable; otherwise say that explicitly and inspect local README/docs. State the issue's current state, labels/owner or overlapping PR, and the smallest usable shared-authoritative-instance path for a Fio PM session. Distinguish the published 0.2.0 per-client stdio MCP path from a shared process and give concrete readiness criteria. Do not edit files or start implementation. Be concise."

  result = call.("ask", %{"instance" => "pm-server-81-inspect", "agent" => "inspect", "prompt" => prompt, "timeout_ms" => 180_000})
  IO.puts(result["text"] || inspect(result))
after
  Snodo.Client.close(client)
end

release = "/tmp/gen_agent_server_claude_023/_build/prod/rel/gen_agent_server/bin/gen_agent_server"
project = "/tmp/gen_agent_claude_options_117"
{:ok, client} = Snodo.Client.connect({:stdio, release, ["eval", "GenAgentServer.MCP.serve()"]}, timeout: 420_000)

call = fn name, args ->
  case Snodo.Client.call_tool(client, name, args, timeout: 420_000) do
    {:ok, %{"isError" => true} = response} -> raise "#{name}: #{inspect(response)}"
    {:ok, %{"structuredContent" => value}} -> value
    other -> raise "#{name}: #{inspect(other)}"
  end
end

try do
  config = %{
    "cwd" => project,
    "routes" => [%{"name" => "review", "provider" => "codex", "model" => "gpt-6-astra", "effort" => "high"}]
  }
  call.("create_instance", %{"instance" => "pm-core-118-review", "config" => config})

  prompt = "Read-only final review of the six-file uncommitted diff for gen_agent issue #118 in integrations/claude. Inspect the issue via gh if available, the diff, adjacent code, and relevant tests. Verify it addresses successful result text fallback, preserving raw success fields, and useful messages for errors arrays without regressing other event shapes. The host separately verified format, warnings-as-errors compile, strict Credo, Dialyzer, docs, and 90 passing tests (3 excluded) after rebuilding a stale test-only claude_wrapper artifact. Do not edit or run network-changing commands. Output APPROVE or REQUEST CHANGES, with only concrete blocking findings and file/line references."

  result = call.("ask", %{"instance" => "pm-core-118-review", "agent" => "review", "prompt" => prompt, "timeout_ms" => 360_000})
  IO.puts(result["text"] || inspect(result))
  IO.inspect(Map.take(result, ["status", "session_id"]), label: "metadata")
after
  Snodo.Client.close(client)
end

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
    "routes" => [%{"name" => "diagnose", "provider" => "codex", "model" => "gpt-6-luna", "effort" => "low", "codex_sandbox" => "workspace_write"}]
  }
  call.("create_instance", %{"instance" => "pm-core-118-rebuild", "config" => config})

  prompt = "Diagnose the three gen_agent issue #118 executable-conformance test failures from the previous verification. Those failures said the compiled cached claude_wrapper lacks ClaudeWrapper.Runner.Forcola.stream_lines/4; 87 tests passed, 3 excluded, 3 failed. In integrations/claude, inspect the locked claude_wrapper version, source function definition, compiled module exports/path, and relevant test setup. Do not change source, tests, docs, or the lockfile. If this is only stale compiled dependency output, rebuild the minimum local dependency artifacts without fetching network dependencies, then rerun mix test with MIX_OS_CONCURRENCY_LOCK=0. If the locked source truly lacks the function, stop and report the package/version mismatch instead of altering dependencies. Report exact commands, exit codes, and final test count."

  result = call.("ask", %{"instance" => "pm-core-118-rebuild", "agent" => "diagnose", "prompt" => prompt, "timeout_ms" => 360_000})
  IO.puts(result["text"] || inspect(result))
  IO.inspect(Map.take(result, ["status", "session_id"]), label: "metadata")
after
  Snodo.Client.close(client)
end

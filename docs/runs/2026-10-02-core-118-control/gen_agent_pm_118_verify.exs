release = "/tmp/gen_agent_server_claude_023/_build/prod/rel/gen_agent_server/bin/gen_agent_server"
project = "/tmp/gen_agent_claude_options_117"
{:ok, client} = Snodo.Client.connect({:stdio, release, ["eval", "GenAgentServer.MCP.serve()"]}, timeout: 600_000)

call = fn name, args ->
  case Snodo.Client.call_tool(client, name, args, timeout: 600_000) do
    {:ok, %{"isError" => true} = response} -> raise "#{name}: #{inspect(response)}"
    {:ok, %{"structuredContent" => value}} -> value
    other -> raise "#{name}: #{inspect(other)}"
  end
end

try do
  config = %{
    "cwd" => project,
    "routes" => [%{"name" => "verify", "provider" => "codex", "model" => "gpt-6-luna", "effort" => "low", "codex_sandbox" => "workspace_write"}]
  }

  IO.inspect(call.("create_instance", %{"instance" => "pm-core-118-verify", "config" => config}), label: "created")

  prompt = "Verify the existing uncommitted fix for gen_agent issue #118. Do not edit source, tests, or docs, and do not commit/push. In integrations/claude, run the package quality gates from CONTRIBUTING.md: mix format --check-formatted, mix compile --warnings-as-errors, mix test, mix credo --strict, mix dialyzer, and mix docs --warnings-as-errors. Set MIX_OS_CONCURRENCY_LOCK=0 if the Codex sandbox blocks the Mix TCP lock. Use only locally installed dependencies; do not fetch network dependencies. Report each command's exit status and useful failure details. If one gate cannot run because of the provider sandbox or tooling, say exactly which and why. Keep the report concise."

  result = call.("ask", %{"instance" => "pm-core-118-verify", "agent" => "verify", "prompt" => prompt, "timeout_ms" => 540_000})
  IO.puts(result["text"] || inspect(result))
  IO.inspect(Map.take(result, ["status", "session_id"]), label: "metadata")
after
  Snodo.Client.close(client)
end

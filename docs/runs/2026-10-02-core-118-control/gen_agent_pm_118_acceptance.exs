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
    "routes" => [%{"name" => "inspect", "provider" => "codex", "model" => "gpt-6-luna", "effort" => "low"}]
  }
  call.("create_instance", %{"instance" => "pm-core-118-acceptance", "config" => config})

  prompt = "Read-only audit of issue #118's final acceptance item. The issue requests: 'Capture one real failed result per subtype from the CLI and use it as a fixture.' Inspect the current committed diff and any pre-existing real CLI recordings/fixtures in integrations/claude. State whether that exact item is satisfied, partially satisfied, or infeasible with the available recordings; list the relevant subtypes and paths. Also state whether the other three behavioral regression scenarios have executable tests. Do not edit files, commit, push, or access GitHub. Be precise and concise."

  result = call.("ask", %{"instance" => "pm-core-118-acceptance", "agent" => "inspect", "prompt" => prompt, "timeout_ms" => 180_000})
  IO.puts(result["text"] || inspect(result))
after
  Snodo.Client.close(client)
end

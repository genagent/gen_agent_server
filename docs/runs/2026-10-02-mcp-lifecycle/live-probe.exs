release = Path.expand("_build/prod/rel/gen_agent_server/bin/gen_agent_server")
cwd = File.cwd!()
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
    "cwd" => cwd,
    "routes" => [
      %{"name" => "codex", "provider" => "codex", "model" => "gpt-6-luna", "effort" => "low"},
      %{"name" => "claude", "provider" => "claude", "model" => "haiku", "effort" => "low"}
    ]
  }

  IO.inspect(call.("create_instance", %{"instance" => "model-probe", "config" => config}), label: "created")

  for route <- ["codex", "claude"] do
    result = call.("ask", %{"instance" => "model-probe", "agent" => route, "prompt" => "Reply with exactly READY and nothing else.", "timeout_ms" => 120_000})
    IO.inspect(Map.take(result, ["status", "text", "session_id", "usage"]), label: route)
  end

  IO.inspect(call.("stop_instance", %{"instance" => "model-probe"}), label: "stopped")
after
  Snodo.Client.close(client)
end

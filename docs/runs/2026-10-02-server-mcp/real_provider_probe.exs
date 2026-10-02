release = Path.expand("_build/prod/rel/gen_agent_server/bin/gen_agent_server")
{:ok, client} =
  Snodo.Client.connect(
    {:stdio, release, ["eval", "GenAgentServer.MCP.serve()"]},
    timeout: 180_000
  )

try do
  for provider <- ~w(codex claude) do
    started = System.monotonic_time(:millisecond)

    result =
      Snodo.Client.call_tool(
        client,
        "ask",
        %{
          "agent" => provider,
          "prompt" => "Reply with exactly READY. Do not inspect files or use tools.",
          "timeout_ms" => 120_000
        },
        timeout: 180_000
      )

    elapsed = System.monotonic_time(:millisecond) - started

    case result do
      {:ok, %{"structuredContent" => %{"text" => text} = content}} ->
        unless String.contains?(text, "READY"), do: raise("#{provider} did not respond READY: #{inspect(content)}")
        IO.puts("#{provider} MCP ask: READY in #{elapsed}ms; session_id=#{inspect(content["session_id"])}")

      other ->
        raise "#{provider} MCP ask failed in #{elapsed}ms: #{inspect(other)}"
    end
  end
after
  Snodo.Client.close(client)
end

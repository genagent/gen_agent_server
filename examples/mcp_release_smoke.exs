# Run after `MIX_ENV=prod mix release` to check the packaged MCP entry point.
release = Path.expand("_build/prod/rel/gen_agent_server/bin/gen_agent_server")

{:ok, client} =
  Snodo.Client.connect({:stdio, release, ["eval", "GenAgentServer.MCP.serve()"]})

try do
  {:ok, tools} = Snodo.Client.list_tools(client)
  names = Enum.map(tools, & &1["name"]) |> Enum.sort()
  expected = ~w(agents ask instances invoke result status)

  unless names == expected, do: raise("wrong MCP catalogue: #{inspect(names)}")

  {:ok, asked} =
    Snodo.Client.call_tool(client, "ask", %{"agent" => "echo", "prompt" => "release"})

  unless get_in(asked, ["structuredContent", "text"]) == "echo: release",
    do: raise("MCP ask failed: #{inspect(asked)}")

  {:ok, invoked} =
    Snodo.Client.call_tool(client, "invoke", %{"agent" => "echo", "prompt" => "repeat"})

  id = get_in(invoked, ["structuredContent", "id"]) || raise("MCP invoke failed")

  read = fn ->
    {:ok, result} = Snodo.Client.call_tool(client, "result", %{"id" => id})
    result["structuredContent"]
  end

  result =
    Enum.reduce_while(1..100, nil, fn _, _ ->
      case read.() do
        %{"status" => "completed"} = data ->
          {:halt, data}

        _ ->
          Process.sleep(10)
          {:cont, nil}
      end
    end)

  unless result && result["text"] == "echo: repeat" && read.() == result,
    do: raise("MCP result was not repeatable: #{inspect(result)}")

  IO.puts("MCP release smoke passed")
after
  Snodo.Client.close(client)
end

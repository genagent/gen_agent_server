# Run after `MIX_ENV=prod mix release` to check the packaged MCP entry point.
release = Path.expand("_build/prod/rel/gen_agent_server/bin/gen_agent_server")

{:ok, client} =
  Snodo.Client.connect({:stdio, release, ["eval", "GenAgentServer.MCP.serve()"]})

try do
  {:ok, discovery} = Snodo.Client.discover(client)

  unless discovery["instructions"] =~ "gen-agent://guide/quickstart",
    do: raise("MCP instructions are missing")

  {:ok, resources} = Snodo.Client.list_resources(client)

  unless Enum.map(resources, & &1["uri"]) == ["gen-agent://guide/quickstart"],
    do: raise("MCP quickstart resource is missing")

  {:ok, %{"contents" => [%{"text" => guide}]}} =
    Snodo.Client.read_resource(client, "gen-agent://guide/quickstart")

  unless guide =~ "create_instance" and guide =~ "to a read-only sandbox",
    do: raise("MCP quickstart is incomplete")

  {:ok, tools} = Snodo.Client.list_tools(client)
  names = Enum.map(tools, & &1["name"]) |> Enum.sort()

  expected =
    ~w(agents ask create_instance describe_instance instances invoke result status stop_instance)

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

  # Lifecycle: provider routes need a CLI and credentials, so the packaged
  # check creates echo routes and confirms provider validation without starting
  # anything. Model selection through a backend is covered by the test suite.
  call = fn name, args ->
    {:ok, result} = Snodo.Client.call_tool(client, name, args)
    result
  end

  text = fn result -> result["content"] |> Enum.map_join(" ", & &1["text"]) end

  config = %{
    "max_in_flight" => 3,
    "routes" => [
      %{"name" => "one", "provider" => "echo"},
      %{"name" => "two", "provider" => "echo"}
    ]
  }

  created = call.("create_instance", %{"instance" => "pm", "config" => config})
  data = created["structuredContent"] || raise("create_instance failed: #{inspect(created)}")

  unless data["configured"] == true and Enum.map(data["routes"], & &1["name"]) == ["one", "two"] and
           data["limits"] == %{"max_in_flight" => 3, "max_results" => 100},
         do: raise("unexpected created instance: #{inspect(data)}")

  described = call.("describe_instance", %{"instance" => "pm"})

  unless described["structuredContent"] == data,
    do: raise("describe_instance differs from creation: #{inspect(described)}")

  duplicate = call.("create_instance", %{"instance" => "pm", "config" => config})

  unless duplicate["isError"] == true and text.(duplicate) =~ "instance_exists",
    do: raise("duplicate creation was not rejected: #{inspect(duplicate)}")

  bad = %{"routes" => [%{"name" => "x", "provider" => "claude", "model" => "--flag"}]}
  rejected = call.("create_instance", %{"instance" => "bad", "config" => bad})

  unless rejected["isError"] == true and text.(rejected) =~ "invalid_config",
    do: raise("invalid configuration was accepted: #{inspect(rejected)}")

  {:ok, instances} = Snodo.Client.call_tool(client, "instances", %{})

  if "bad" in instances["structuredContent"]["instances"],
    do: raise("rejected configuration created an instance")

  {:ok, pm_asked} =
    Snodo.Client.call_tool(client, "ask", %{
      "instance" => "pm",
      "agent" => "two",
      "prompt" => "lifecycle"
    })

  unless get_in(pm_asked, ["structuredContent", "text"]) == "echo: lifecycle",
    do: raise("ask on created instance failed: #{inspect(pm_asked)}")

  default_name = Enum.find(instances["structuredContent"]["instances"], &(&1 != "pm"))
  protected = call.("stop_instance", %{"instance" => default_name})

  unless protected["isError"] == true and text.(protected) =~ "default_instance",
    do: raise("the default instance was not protected: #{inspect(protected)}")

  stopped = call.("stop_instance", %{"instance" => "pm"})

  unless get_in(stopped, ["structuredContent", "stopped"]) == true,
    do: raise("stop_instance failed: #{inspect(stopped)}")

  gone = call.("describe_instance", %{"instance" => "pm"})

  unless gone["isError"] == true and text.(gone) =~ "instance_not_found",
    do: raise("stopped instance is still described: #{inspect(gone)}")

  IO.puts("MCP release smoke passed")
after
  Snodo.Client.close(client)
end

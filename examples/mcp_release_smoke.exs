# Run after `MIX_ENV=prod mix release` to check the packaged MCP entry point.
release = Path.expand("_build/prod/rel/gen_agent_server/bin/gen_agent_server")

{:ok, client} =
  Snodo.Client.connect({:stdio, release, ["eval", "GenAgentServer.MCP.serve()"]})

try do
  {:ok, discovery} = Snodo.Client.discover(client)

  unless discovery["instructions"] =~ "gen-agent://guide/index",
    do: raise("MCP instructions are missing")

  {:ok, resources} = Snodo.Client.list_resources(client)

  guide_uris =
    ~w(gen-agent://guide/capabilities gen-agent://guide/index gen-agent://guide/invocations gen-agent://guide/peers gen-agent://guide/public-source gen-agent://guide/quickstart gen-agent://guide/scope)

  unless resources |> Enum.map(& &1["uri"]) |> Enum.sort() == guide_uris,
    do: raise("MCP guide catalogue is incomplete")

  {:ok, %{"contents" => [%{"text" => index}]}} =
    Snodo.Client.read_resource(client, "gen-agent://guide/index")

  unless Enum.all?(guide_uris -- ["gen-agent://guide/index"], &String.contains?(index, &1)),
    do: raise("MCP guide index has broken links")

  {:ok, %{"contents" => [%{"text" => guide}]}} =
    Snodo.Client.read_resource(client, "gen-agent://guide/quickstart")

  unless guide =~ "create_instance" and guide =~ "to a read-only sandbox",
    do: raise("MCP quickstart is incomplete")

  {:ok, legacy} =
    Snodo.Client.connect({:stdio, release, ["eval", "GenAgentServer.MCP.serve()"]},
      protocol: "2025-11-25"
    )

  try do
    unless legacy.session.instructions =~ "gen-agent://guide/index",
      do: raise("MCP legacy initialize instructions are missing")

    {:ok, legacy_resources} = Snodo.Client.list_resources(legacy)

    unless legacy_resources |> Enum.map(& &1["uri"]) |> Enum.sort() == guide_uris,
      do: raise("MCP legacy resource catalogue is incomplete")
  after
    Snodo.Client.close(legacy)
  end

  {:ok, tools} = Snodo.Client.list_tools(client)
  names = Enum.map(tools, & &1["name"]) |> Enum.sort()

  expected =
    ~w(agents ask bind_peer create_instance describe_instance discover_peers instances invoke peer_result public_file public_issue public_issues public_revision result send_peer_message status stop_instance)

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

  peer_disabled = call.("discover_peers", %{})

  unless peer_disabled["isError"] == true and text.(peer_disabled) =~ "peers_disabled",
    do: raise("peer opt-in boundary failed: #{inspect(peer_disabled)}")

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

# Start and close a packaged VM before checking IDs in another packaged VM.
{:ok, previous} =
  Snodo.Client.connect({:stdio, release, ["eval", "GenAgentServer.MCP.serve()"]})

old_id =
  try do
    {:ok, invoked} =
      Snodo.Client.call_tool(previous, "invoke", %{"agent" => "echo", "prompt" => "old VM"})

    get_in(invoked, ["structuredContent", "id"]) || raise("old VM invoke failed")
  after
    Snodo.Client.close(previous)
  end

# Stopping the packaged stdio VM and starting it again exercises release
# restart ID semantics without requiring distributed Erlang or an HTTP socket.
{:ok, restarted} =
  Snodo.Client.connect({:stdio, release, ["eval", "GenAgentServer.MCP.serve()"]})

try do
  missing = fn ->
    {:ok, old} = Snodo.Client.call_tool(restarted, "result", %{"id" => old_id})

    unless old["isError"] and
             Enum.any?(old["content"], &String.contains?(&1["text"], "not_found")),
           do: raise("old ID resolved in restarted release")
  end

  missing.()

  {:ok, invoked} =
    Snodo.Client.call_tool(restarted, "invoke", %{"agent" => "echo", "prompt" => "restart"})

  new_id = get_in(invoked, ["structuredContent", "id"]) || raise("restart invoke failed")
  old_namespace = Regex.replace(~r/-\d+\z/, old_id, "")
  new_namespace = Regex.replace(~r/-\d+\z/, new_id, "")
  unless old_namespace != new_namespace, do: raise("release reused invocation namespace")
  missing.()
  IO.puts("MCP release restart ID smoke passed")
after
  Snodo.Client.close(restarted)
end

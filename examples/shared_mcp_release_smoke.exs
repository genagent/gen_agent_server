# Build first: MIX_ENV=prod mix release
# Run: mix run examples/shared_mcp_release_smoke.exs
# This uses a packaged long-lived VM and two independent HTTP clients.
defmodule SharedMCPReleaseSmoke do
  @release Path.expand("_build/prod/rel/gen_agent_server/bin/gen_agent_server")

  def run do
    {:ok, socket} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
    {:ok, {_, port}} = :inet.sockname(socket)
    :gen_tcp.close(socket)
    token = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    opts = [headers: [{"authorization", "Bearer " <> token}], timeout: 5000]
    url = "http://127.0.0.1:#{port}/mcp"

    old =
      with_release(port, token, fn ->
        {:ok, first} = Snodo.Client.connect({:http, url}, opts)
        {:ok, second} = Snodo.Client.connect({:http, url}, opts)

        try do
          {:ok, tools} = Snodo.Client.list_tools(first)
          expected = ~w(agents ask describe_instance instances invoke result status)

          unless Enum.sort(Enum.map(tools, & &1["name"])) == expected,
            do: raise("wrong shared catalogue")

          %{"instances" => ["server/default"]} = call(first, "instances", %{})

          %{"id" => id} =
            call(first, "invoke", %{
              "instance" => "server/default",
              "agent" => "echo",
              "prompt" => "shared release"
            })

          data = completed(second, id)

          unless data["text"] == "echo: shared release" and data == read(first, id),
            do: raise("independent clients did not share a result")

          Snodo.Client.close(first)
          unless data == read(second, id), do: raise("disconnect lost the result")
          id
        after
          Snodo.Client.close(first)
          Snodo.Client.close(second)
        end
      end)

    with_release(port, token, fn ->
      {:ok, client} = Snodo.Client.connect({:http, url}, opts)

      try do
        assert_old_missing(client, old)

        %{"id" => new} =
          call(client, "invoke", %{
            "instance" => "server/default",
            "agent" => "echo",
            "prompt" => "new release"
          })

        unless new != old, do: raise("restarted release reused an invocation ID")
        completed(client, new)
        assert_old_missing(client, old)
      after
        Snodo.Client.close(client)
      end
    end)

    IO.puts("Shared MCP release smoke passed (two HTTP clients, disconnect, restart)")
  end

  defp with_release(port, token, fun) do
    # stdin controls the release lifetime, independently of HTTP client lifetime.
    code =
      ~S|{:ok, _} = Application.ensure_all_started(:gen_agent_server); IO.puts("shared-ready"); IO.gets("")|

    env = %{
      "GEN_AGENT_SERVER_SHARED_MCP_ENABLED" => "true",
      "GEN_AGENT_SERVER_SHARED_MCP_PORT" => to_string(port),
      "GEN_AGENT_SERVER_SHARED_MCP_TOKEN" => token,
      "GEN_AGENT_SERVER_SHARED_MCP_INSTANCES" => ~s(["server/default"]),
      "GEN_AGENT_SERVER_PROVIDERS" => "echo",
      "GEN_AGENT_SERVER_CONFIG" => false,
      "GEN_AGENT_SERVER_PEERS" => "false"
    }

    env =
      Enum.map(env, fn {k, v} ->
        {String.to_charlist(k), if(v == false, do: false, else: String.to_charlist(v))}
      end)

    release =
      Port.open({:spawn_executable, @release}, [
        :binary,
        :exit_status,
        {:line, 65536},
        {:args, ["eval", code]},
        {:env, env}
      ])

    try do
      ready(release)
      fun.()
    after
      Port.command(release, "stop\n")

      receive do
        {^release, {:exit_status, 0}} -> :ok
        {^release, {:exit_status, _}} -> raise("release shutdown failed")
      after
        5000 ->
          Port.close(release)
          raise("release shutdown timed out")
      end
    end
  end

  defp ready(release), do: ready(release, System.monotonic_time(:millisecond) + 10_000)

  defp ready(release, deadline) do
    receive do
      {^release, {:data, {:eol, "shared-ready"}}} -> :ok
      {^release, {:data, _}} -> ready(release, deadline)
      {^release, {:exit_status, _}} -> raise("release failed to start")
    after
      max(deadline - System.monotonic_time(:millisecond), 0) -> raise("release startup timed out")
    end
  end

  defp call(client, name, args) do
    {:ok, data} = Snodo.Client.call_tool(client, name, args)
    if data["isError"], do: raise("shared tool #{name} failed")
    data["structuredContent"]
  end

  defp read(client, id), do: call(client, "result", %{"instance" => "server/default", "id" => id})

  defp completed(client, id, attempts \\ 100) do
    case read(client, id) do
      %{"status" => "completed"} = data ->
        data

      _ when attempts > 0 ->
        Process.sleep(10)
        completed(client, id, attempts - 1)

      _ ->
        raise("invocation did not complete")
    end
  end

  defp assert_old_missing(client, id) do
    {:ok, data} =
      Snodo.Client.call_tool(client, "result", %{"instance" => "server/default", "id" => id})

    unless data["isError"] and
             Enum.any?(data["content"], &String.contains?(&1["text"], "not_found")),
           do: raise("old invocation ID resolved after restart")
  end
end

SharedMCPReleaseSmoke.run()

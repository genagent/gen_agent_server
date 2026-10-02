# Optional live anonymous probe; run after MIX_ENV=prod mix release.
# Uses two independent packaged stdio MCP clients and no GitHub credentials.
release = Path.expand("_build/prod/rel/gen_agent_server/bin/gen_agent_server")
repository = "genagent/gen_agent"

connect = fn ->
  {:ok, client} =
    Snodo.Client.connect({:stdio, release, ["eval", "GenAgentServer.MCP.serve()"]})

  client
end

call = fn client, name, args ->
  {:ok, result} = Snodo.Client.call_tool(client, name, args)

  if result["isError"] do
    raise("#{name} failed: #{inspect(result["content"])}")
  end

  result["structuredContent"] || raise("#{name} returned no structured content")
end

first = connect.()

try do
  revision = call.(first, "public_revision", %{"repository" => repository})
  sha = revision["sha"]

  file =
    call.(first, "public_file", %{
      "repository" => repository,
      "sha" => sha,
      "path" => "README.md"
    })

  issues =
    call.(first, "public_issues", %{
      "repository" => repository,
      "query" => "session",
      "state" => "open"
    })

  issue_number =
    case issues["issues"] do
      [%{"number" => number} | _] -> number
      [] -> raise("issue search returned no matching issue to inspect")
    end

  issue =
    call.(first, "public_issue", %{
      "repository" => repository,
      "number" => issue_number
    })

  unless String.length(sha) == 40 and file["sha"] == sha and
           String.starts_with?(file["text"], "# GenAgent") and
           issue["number"] == issue_number and issue["state"] == "open",
         do: raise("public-source response was incomplete")

  second = connect.()

  try do
    repeated =
      call.(second, "public_file", %{
        "repository" => repository,
        "sha" => sha,
        "path" => "README.md"
      })

    unless repeated["text"] == file["text"],
      do: raise("a fresh client received different text for the same commit")

    IO.puts(
      "Public source release probe passed: #{sha}, issue ##{issue_number} #{issue["state"]}"
    )
  after
    Snodo.Client.close(second)
  end
after
  Snodo.Client.close(first)
end

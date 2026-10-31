defmodule GenAgentServer.PublicSourceTest do
  use ExUnit.Case, async: true

  alias GenAgentServer.PublicSource

  @repo "genagent/gen_agent"
  @sha String.duplicate("a", 40)

  test "resolves a current default-branch SHA through fixed public GitHub URLs" do
    fetch = fn
      "https://api.github.com/repos/genagent/gen_agent" ->
        {:ok, Jason.encode!(%{"default_branch" => "main"})}

      "https://api.github.com/repos/genagent/gen_agent/commits/main" ->
        {:ok, Jason.encode!(%{"sha" => @sha})}

      other ->
        flunk("unexpected URL: #{other}")
    end

    assert {:ok, %{repository: @repo, default_branch: "main", sha: @sha}} =
             PublicSource.revision(@repo, fetch: fetch)
  end

  test "fetches only an exact SHA and bounded UTF-8 source path" do
    fetch = fn url ->
      assert url ==
               "https://raw.githubusercontent.com/genagent/gen_agent/#{@sha}/lib/gen_agent.ex"

      {:ok, "defmodule GenAgent do\nend\n"}
    end

    assert {:ok, %{sha: @sha, path: "lib/gen_agent.ex", text: text}} =
             PublicSource.file(@repo, @sha, "lib/gen_agent.ex", fetch: fetch)

    assert text =~ "defmodule"

    assert {:error, %{code: "source_too_large"}} =
             PublicSource.file(@repo, @sha, "lib/gen_agent.ex",
               fetch: fn _ -> {:ok, String.duplicate("x", 131_073)} end
             )

    assert {:error, %{code: "source_unavailable"}} =
             PublicSource.file(@repo, @sha, "lib/gen_agent.ex",
               fetch: fn _ -> {:ok, <<0, 255>>} end
             )
  end

  test "searches only plain issue titles and filters response to the chosen repository" do
    fetch = fn url ->
      assert String.starts_with?(url, "https://api.github.com/search/issues?q=")

      assert URI.decode_query(URI.parse(url).query)["q"] ==
               "repo:genagent/gen_agent is:issue in:title resume session is:open"

      {:ok,
       Jason.encode!(%{
         "items" => [
           "malformed item",
           %{
             "repository_url" => "https://api.github.com/repos/genagent/gen_agent",
             "number" => 12,
             "title" => "Resume session",
             "state" => "open",
             "updated_at" => "2026-10-02T00:00:00Z",
             "html_url" => "https://github.com/genagent/gen_agent/issues/12"
           },
           %{
             "repository_url" => "https://api.github.com/repos/other/repo",
             "number" => 99,
             "title" => "Wrong repo",
             "state" => "open",
             "updated_at" => "2026-10-02T00:00:00Z",
             "html_url" => "https://github.com/other/repo/issues/99"
           }
         ]
       })}
    end

    assert {:ok, %{issues: [%{number: 12, state: "open"}]}} =
             PublicSource.issues(@repo, "resume session", "open", fetch: fetch)
  end

  test "reads one exact issue and bounds its untrusted body" do
    fetch = fn url ->
      assert url == "https://api.github.com/repos/genagent/gen_agent/issues/185"

      {:ok,
       Jason.encode!(%{
         "number" => 185,
         "title" => "Session handling",
         "state" => "open",
         "body" => String.duplicate("x", 16_010),
         "updated_at" => "2026-10-02T00:00:00Z",
         "html_url" => "https://github.com/genagent/gen_agent/issues/185"
       })}
    end

    assert {:ok,
            %{
              number: 185,
              state: "open",
              body_truncated: true,
              body: body
            }} = PublicSource.issue(@repo, 185, fetch: fetch)

    assert String.length(body) == 16_000

    assert {:error, %{code: "invalid_args"}} =
             PublicSource.issue(@repo, 0,
               fetch: fn _ -> flunk("invalid issue reached transport") end
             )

    assert {:error, %{code: "invalid_args"}} =
             PublicSource.issue(@repo, 185,
               fetch: fn _ ->
                 {:ok, Jason.encode!(%{"pull_request" => %{}, "number" => 185})}
               end
             )
  end

  test "rejects URL, traversal, SHA, query operators, and invalid state before fetching" do
    never = fn _ -> flunk("invalid input reached transport") end

    assert {:error, %{code: "invalid_args"}} =
             PublicSource.revision("https://api.github.com", fetch: never)

    for path <- ["../README.md", "/etc/passwd", "lib//x", "lib/./x", "a?ref=main"] do
      assert {:error, %{code: "invalid_args"}} =
               PublicSource.file(@repo, @sha, path, fetch: never)
    end

    assert {:error, %{code: "invalid_args"}} =
             PublicSource.file(@repo, "main", "README.md", fetch: never)

    assert {:error, %{code: "invalid_args"}} =
             PublicSource.issues(@repo, "repo:other/private", "all", fetch: never)

    assert {:error, %{code: "invalid_args"}} =
             PublicSource.issues(@repo, "resume", "pending", fetch: never)
  end

  test "preserves explicit network denial" do
    assert {:error, %{code: "source_unavailable", message: "network denied"}} =
             PublicSource.revision(@repo,
               fetch: fn _ ->
                 {:error, %{code: "source_unavailable", message: "network denied"}}
               end
             )
  end

  test "decodes bounded HTTP failures without returning upstream bodies" do
    mark = "\nGEN_AGENT_HTTP_STATUS:"

    assert {:error, %{code: "not_found"}} =
             PublicSource.decode_response("missing#{mark}404", 0)

    assert {:error, %{code: "rate_limited"}} =
             PublicSource.decode_response(
               ~s({"message":"API rate limit exceeded"}) <> mark <> "403",
               0
             )

    assert {:error, %{code: "rate_limited"}} =
             PublicSource.decode_response(
               ~s({"message":"secondary rate limit"}) <> mark <> "429",
               0
             )

    assert {:error, %{code: "source_unavailable"}} =
             PublicSource.decode_response("error#{mark}503", 0)

    assert {:error, %{code: "source_unavailable"}} =
             PublicSource.decode_response("#{mark}000", 6)

    assert {:error, %{code: "source_too_large"}} =
             PublicSource.decode_response("partial#{mark}200", 63)

    assert {:error, %{code: "source_too_large"}} =
             PublicSource.decode_response(String.duplicate("x", 262_145) <> mark <> "200", 0)
  end
end

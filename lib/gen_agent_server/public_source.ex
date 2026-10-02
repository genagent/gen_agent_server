defmodule GenAgentServer.PublicSource do
  @moduledoc """
  Bounded, anonymous reads of public GitHub source and issue metadata.

  URLs are assembled from validated repository, SHA, path, and search terms.
  Callers cannot supply hosts, headers, credentials, redirects, or curl flags.
  The transport disables curl's user configuration and never uses `gh` auth.
  Returned source is untrusted content, not server instructions.
  """

  @max_body 262_144
  @max_file 131_072
  @max_issue_body 16_000
  @api "https://api.github.com"
  @raw "https://raw.githubusercontent.com"

  @doc "Resolve a public repository's default branch to its current commit SHA."
  def revision(repository, opts \\ []) do
    with :ok <- repository(repository),
         {:ok, metadata} <- json("#{@api}/repos/#{repository}", opts),
         {:ok, branch} <- default_branch(metadata),
         {:ok, commit} <-
           json("#{@api}/repos/#{repository}/commits/#{URI.encode_www_form(branch)}", opts),
         {:ok, sha} <- commit_sha(commit) do
      {:ok, %{repository: repository, default_branch: branch, sha: sha}}
    end
  end

  @doc "Read at most 128 KiB of UTF-8 text from an exact public commit."
  def file(repository, sha, path, opts \\ []) do
    with :ok <- repository(repository),
         :ok <- sha(sha),
         :ok <- path(path),
         {:ok, body} <- request("#{@raw}/#{repository}/#{sha}/#{path}", opts),
         :ok <- text_file(body) do
      {:ok, %{repository: repository, sha: sha, path: path, text: body}}
    end
  end

  @doc "Search issue titles in a public repository, returning up to 20 states."
  def issues(repository, query, state \\ "all", opts \\ []) do
    with :ok <- repository(repository),
         :ok <- query(query),
         :ok <- state(state) do
      qualifier = if state == "all", do: "", else: " is:#{state}"
      search = "repo:#{repository} is:issue in:title #{query}#{qualifier}"
      url = "#{@api}/search/issues?q=#{URI.encode_www_form(search)}&per_page=20"

      with {:ok, data} <- json(url, opts),
           {:ok, items} <- issue_items(data, repository) do
        {:ok, %{repository: repository, query: query, state: state, issues: items}}
      end
    end
  end

  @doc "Read a specific public issue for an exact duplicate/ownership check."
  def issue(repository, number, opts \\ []) do
    with :ok <- repository(repository),
         :ok <- issue_number(number),
         {:ok, data} <- json("#{@api}/repos/#{repository}/issues/#{number}", opts),
         {:ok, issue} <- issue_detail(data, repository, number) do
      {:ok, issue}
    end
  end

  defp repository(value) when is_binary(value) do
    if byte_size(value) <= 201 and
         Regex.match?(
           ~r/\A[A-Za-z0-9][A-Za-z0-9_.-]{0,99}\/[A-Za-z0-9][A-Za-z0-9_.-]{0,99}\z/,
           value
         ),
       do: :ok,
       else: invalid("repository must be an owner/repo name")
  end

  defp repository(_), do: invalid("repository must be an owner/repo name")

  defp sha(value) when is_binary(value) do
    if Regex.match?(~r/\A[0-9a-fA-F]{40}\z/, value),
      do: :ok,
      else: invalid("sha must be a full 40-character commit ID")
  end

  defp sha(_), do: invalid("sha must be a full 40-character commit ID")

  defp path(value) when is_binary(value) do
    segments = String.split(value, "/")

    if byte_size(value) <= 512 and
         Regex.match?(~r/\A[A-Za-z0-9_.\/-]+\z/, value) and
         Enum.all?(segments, &(&1 not in ["", ".", ".."])),
       do: :ok,
       else: invalid("path must be a relative source path without traversal")
  end

  defp path(_), do: invalid("path must be a relative source path without traversal")

  defp query(value) when is_binary(value) do
    if byte_size(value) <= 128 and Regex.match?(~r/\A[A-Za-z0-9][A-Za-z0-9._ -]*\z/, value),
      do: :ok,
      else: invalid("query must be 1 to 128 plain search characters")
  end

  defp query(_), do: invalid("query must be 1 to 128 plain search characters")

  defp state(value) when value in ["all", "open", "closed"], do: :ok
  defp state(_), do: invalid("state must be all, open, or closed")

  defp issue_number(value) when is_integer(value) and value > 0 and value <= 999_999_999,
    do: :ok

  defp issue_number(_), do: invalid("number must be a positive issue number")

  defp default_branch(%{"default_branch" => branch})
       when is_binary(branch) and byte_size(branch) > 0 and byte_size(branch) <= 200,
       do: {:ok, branch}

  defp default_branch(_), do: unavailable("repository metadata has no default branch")

  defp commit_sha(%{"sha" => value}) do
    case sha(value) do
      :ok -> {:ok, String.downcase(value)}
      _ -> unavailable("commit response has no valid SHA")
    end
  end

  defp commit_sha(_), do: unavailable("commit response has no valid SHA")

  defp issue_items(%{"items" => items}, repository) when is_list(items) do
    expected = "#{@api}/repos/#{repository}"

    mapped =
      items
      |> Enum.filter(fn item ->
        is_map(item) and is_binary(item["repository_url"]) and
          String.downcase(item["repository_url"]) == String.downcase(expected) and
          not Map.has_key?(item, "pull_request")
      end)
      |> Enum.take(20)
      |> Enum.map(fn item ->
        %{
          number: item["number"],
          title: item["title"],
          state: item["state"],
          updated_at: item["updated_at"],
          url: item["html_url"]
        }
      end)

    if Enum.all?(mapped, &valid_issue?/1),
      do: {:ok, mapped},
      else: unavailable("issue search returned malformed metadata")
  end

  defp issue_items(_, _), do: unavailable("issue search returned malformed metadata")

  defp issue_detail(%{"pull_request" => _}, _repository, _number),
    do: invalid("number identifies a pull request, not an issue")

  defp issue_detail(%{"number" => number, "body" => body} = data, repository, number)
       when is_binary(body) do
    issue = %{
      repository: repository,
      number: number,
      title: data["title"],
      state: data["state"],
      body: String.slice(body, 0, @max_issue_body),
      body_truncated: String.length(body) > @max_issue_body,
      updated_at: data["updated_at"],
      url: data["html_url"]
    }

    if valid_issue?(issue),
      do: {:ok, issue},
      else: unavailable("issue response contained malformed metadata")
  end

  defp issue_detail(%{"number" => number, "body" => nil} = data, repository, number),
    do: issue_detail(Map.put(data, "body", ""), repository, number)

  defp issue_detail(_, _, _), do: unavailable("issue response contained malformed metadata")

  defp valid_issue?(%{number: number, title: title, state: state, updated_at: updated, url: url}) do
    is_integer(number) and number > 0 and is_binary(title) and
      state in ["open", "closed"] and is_binary(updated) and is_binary(url) and
      String.starts_with?(url, "https://github.com/")
  end

  defp text_file(body) when byte_size(body) <= @max_file do
    if String.valid?(body) and not String.contains?(body, <<0>>),
      do: :ok,
      else: unavailable("source file is not UTF-8 text")
  end

  defp text_file(_), do: error("source_too_large", "source file exceeds 128 KiB")

  defp json(url, opts) do
    with {:ok, body} <- request(url, opts),
         {:ok, data} <- Jason.decode(body) do
      {:ok, data}
    else
      {:error, %{code: _, message: _} = error} -> {:error, error}
      _ -> unavailable("public GitHub returned invalid JSON")
    end
  end

  defp request(url, opts) do
    fetch = Keyword.get(opts, :fetch, &curl/1)
    fetch.(url)
  end

  defp curl(url) do
    case System.find_executable("curl") do
      nil -> unavailable("curl is not installed on the server host")
      executable -> curl(executable, url)
    end
  end

  defp curl(executable, url) do
    args = [
      "-q",
      "--silent",
      "--max-time",
      "15",
      "--connect-timeout",
      "5",
      "--max-filesize",
      Integer.to_string(@max_body),
      "--proto",
      "=https",
      "--header",
      "Accept: application/vnd.github+json",
      "--header",
      "User-Agent: gen-agent-server",
      "--write-out",
      "\nGEN_AGENT_HTTP_STATUS:%{http_code}",
      url
    ]

    case System.cmd(executable, args, stderr_to_stdout: false) do
      {output, status} -> decode_response(output, status)
    end
  rescue
    _ -> unavailable("public GitHub request could not start")
  end

  @doc false
  def decode_response(output, exit_status) do
    case Regex.run(~r/\nGEN_AGENT_HTTP_STATUS:(\d{3})\z/, output, return: :index) do
      [{at, _len}, {code_at, code_len}] ->
        body = binary_part(output, 0, at)
        code = output |> binary_part(code_at, code_len) |> String.to_integer()
        response_status(body, code, exit_status)

      _ ->
        unavailable("public GitHub request failed (curl exit #{exit_status})")
    end
  end

  defp response_status(_body, _code, 63),
    do: error("source_too_large", "response exceeds 256 KiB")

  defp response_status(_body, _code, exit_status) when exit_status != 0,
    do: unavailable("public GitHub request failed (curl exit #{exit_status})")

  defp response_status(body, code, 0) when code in 200..299 and byte_size(body) <= @max_body,
    do: {:ok, body}

  defp response_status(body, code, 0) when code in 200..299 and byte_size(body) > @max_body,
    do: error("source_too_large", "response exceeds 256 KiB")

  defp response_status(_body, 404, 0), do: error("not_found", "public GitHub resource not found")

  defp response_status(body, code, 0) when code in [403, 429] do
    if String.contains?(String.downcase(body), "rate limit"),
      do: error("rate_limited", "public GitHub API rate limit reached"),
      else: unavailable("public GitHub denied the request")
  end

  defp response_status(_body, code, 0),
    do: unavailable("public GitHub returned HTTP #{code}")

  defp invalid(message), do: error("invalid_args", message)
  defp unavailable(message), do: error("source_unavailable", message)
  defp error(code, message), do: {:error, %{code: code, message: message}}
end

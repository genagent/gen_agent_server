defmodule GenAgentServer.MCP.Shared.Gate do
  @moduledoc false
  @behaviour Snodo.Transport.StreamableHTTP.RequestGate
  alias Snodo.Transport.StreamableHTTP.Response

  @impl true
  def init(opts, %{path: "/mcp"}), do: Map.new(opts)

  @impl true
  def check(request, config) do
    # Check Host/Origin before body admission as well as in Snodo's adapter.
    authority = "127.0.0.1:#{config.port}"

    cond do
      not authenticated?(headers(request, "authorization"), config.token_hash) ->
        refusal(401, "Unauthorized", [{"www-authenticate", "Bearer"}])

      headers(request, "host") != [authority] or
          headers(request, "origin") not in [[], ["http://" <> authority]] ->
        refusal(403, "Forbidden")

      request.path != "/mcp" ->
        refusal(404, "Not found")

      true ->
        {:ok, %{shared_mcp: true, instances: config.instances}}
    end
  end

  defp headers(request, name), do: for({^name, value} <- request.headers, do: value)

  defp authenticated?(["Bearer " <> token], expected) when byte_size(token) in 32..256,
    do: :crypto.hash_equals(:crypto.hash(:sha256, token), expected)

  defp authenticated?(_, _), do: false

  defp refusal(status, message, headers \\ []) do
    {:response,
     %Response{
       status: status,
       headers: [{"content-type", "application/json"} | headers],
       body: Jason.encode!(%{jsonrpc: "2.0", id: nil, error: %{code: -32003, message: message}})
     }}
  end
end

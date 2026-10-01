defmodule GenAgentServer.Ops.Remote do
  @moduledoc """
  Release-side entry point for running an operation over `rpc`.

  `main/2` runs inside the release and prints one JSON envelope:
  `{"ok": true, "data": ...}` or `{"ok": false, "error": {"code": ..., "message": ...}}`.
  """

  @doc false
  def expression(name, args) when is_binary(name) and is_map(args) do
    json = Jason.encode!(args)

    "GenAgentServer.Ops.Remote.main(#{inspect(name)}, #{inspect(json, limit: :infinity, printable_limit: :infinity)})"
  end

  @doc false
  def main(name, json) do
    # rpc output goes through the release's standard_io, which defaults to
    # latin1 (genagent/gen_agent_server#27).
    :io.setopts(:standard_io, encoding: :unicode)

    envelope =
      case GenAgentServer.Ops.call(name, Jason.decode!(json)) do
        {:ok, data} -> %{ok: true, data: data}
        {:error, error} -> %{ok: false, error: error}
      end

    IO.puts(Jason.encode!(envelope))
  end

  @doc "Run an operation against a running release and decode its envelope."
  def call(release_bin, name, args, opts \\ []) do
    case GenAgentServer.Remote.run_expression(release_bin, expression(name, args), opts) do
      {:error, :timeout} ->
        {:error, %{code: "rpc_timeout", message: "release RPC timed out"}}

      {output, 0} ->
        decode(output)

      {output, status} ->
        {:error,
         %{code: "rpc_failed", message: "release rpc exited #{status}: #{String.trim(output)}"}}
    end
  end

  defp decode(output) do
    # The envelope is the last line; anything before it is release log output.
    line = output |> String.trim() |> String.split("\n") |> List.last()

    case Jason.decode(line || "") do
      {:ok, %{"ok" => true, "data" => data}} -> {:ok, data}
      {:ok, %{"ok" => false, "error" => error}} -> {:error, error}
      _ -> {:error, %{code: "rpc_bad_output", message: String.trim(output)}}
    end
  end
end

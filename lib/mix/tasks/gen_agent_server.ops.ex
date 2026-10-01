defmodule Mix.Tasks.GenAgentServer.Ops do
  @moduledoc """
  Run a `GenAgentServer.Ops` operation locally or against a running release.

      mix gen_agent_server.ops                       # list operations
      mix gen_agent_server.ops NAME --help           # show parameters
      mix gen_agent_server.ops NAME [--PARAM VALUE ...] [--remote]

  Parameters come from the catalogue. String and integer parameters take one
  value; list parameters repeat (`--prompts a --prompts b`); object parameters
  take JSON or `@path/to/file.json`. Parameter names use underscores, as in
  `--timeout_ms`. Output is a JSON document on stdout; errors exit non-zero
  with the error JSON on stderr.

  Without `--remote` the operation runs in a fresh local application, so state
  such as invocation results lasts only for the command. With `--remote` it
  runs in the release named by `RELEASE_NODE`, using the release binary at
  `GEN_AGENT_SERVER_RELEASE_BIN` or the default `_build/prod` path.
  """
  @shortdoc "Run a server operation (local or --remote) with JSON output"
  use Mix.Task

  alias GenAgentServer.Ops

  @impl true
  def run([]) do
    compile_quietly()
    unicode_stdout()

    for op <- Ops.list() do
      mode = if op.mutates, do: "write", else: "read "
      IO.puts("#{String.pad_trailing(op.name, 14)} #{mode}  #{op.summary}")
    end
  end

  def run([name | argv]) do
    compile_quietly()
    unicode_stdout()

    op =
      case Ops.fetch(name) do
        {:ok, op} -> op
        {:error, e} -> Mix.raise(e.message <> "; run mix gen_agent_server.ops to list operations")
      end

    if "--help" in argv do
      print_help(op)
    else
      {remote?, argv} = {"--remote" in argv, List.delete(argv, "--remote")}
      args = parse_args!(op, argv)

      result =
        if remote? do
          Ops.Remote.call(release_bin!(), name, args, timeout_ms: rpc_timeout(op, args))
        else
          Mix.Task.run("app.start")
          Ops.call(name, args)
        end

      case result do
        {:ok, data} ->
          IO.puts(Jason.encode!(data, pretty: true))

        {:error, error} ->
          IO.puts(:stderr, Jason.encode!(error))
          exit({:shutdown, 1})
      end
    end
  end

  defp parse_args!(op, argv) do
    switches =
      Enum.map(op.params, fn p ->
        {String.to_atom(p.name), if(p.type == :string_list, do: :keep, else: :string)}
      end)

    {parsed, rest, invalid} = OptionParser.parse(argv, strict: switches)

    if rest != [] or invalid != [] do
      Mix.raise("unexpected arguments: #{inspect(rest ++ invalid)}; see --help")
    end

    by_name = Map.new(op.params, &{&1.name, &1})

    parsed
    |> Enum.group_by(fn {k, _} -> Atom.to_string(k) end, fn {_, v} -> v end)
    |> Map.new(fn {key, values} -> {key, convert!(by_name[key], values)} end)
  end

  defp convert!(%{type: :string_list}, values), do: values
  defp convert!(%{type: :string}, values), do: List.last(values)

  defp convert!(%{type: :integer, name: name}, values) do
    case Integer.parse(List.last(values)) do
      {n, ""} -> n
      _ -> Mix.raise("--#{name} must be an integer")
    end
  end

  defp convert!(%{type: :object, name: name}, values) do
    raw =
      case List.last(values) do
        "@" <> path -> File.read!(path)
        json -> json
      end

    case Jason.decode(raw) do
      {:ok, map} when is_map(map) -> map
      _ -> Mix.raise("--#{name} must be a JSON object or @file")
    end
  end

  defp print_help(op) do
    IO.puts("#{op.name}: #{op.summary}#{if op.mutates, do: " (changes state)", else: ""}\n")

    for p <- op.params do
      req = if p.required, do: "required", else: "optional"
      IO.puts("  --#{String.pad_trailing(p.name, 12)} #{p.type}, #{req}. #{p.doc}")
    end
  end

  # Waiting operations get the long ask timeout; the rest the control timeout.
  defp rpc_timeout(%{name: name}, args) when name in ["ask", "run_pattern"],
    do: (args["timeout_ms"] || 3_600_000) + 30_000

  defp rpc_timeout(_op, _args), do: 30_000

  defp release_bin! do
    bin =
      System.get_env("GEN_AGENT_SERVER_RELEASE_BIN") ||
        Path.expand("_build/prod/rel/gen_agent_server/bin/gen_agent_server")

    if File.regular?(bin), do: bin, else: Mix.raise("server release not found at #{bin}")
  end

  defp unicode_stdout, do: :io.setopts(:standard_io, encoding: :unicode)

  # Mix compilation notices go to stdout by default. Keep the operation's
  # stdout as one JSON document even on its first invocation after a checkout.
  defp compile_quietly do
    shell = Mix.shell()

    try do
      Mix.shell(Mix.Shell.Quiet)
      Mix.Task.run("compile")
    after
      Mix.shell(shell)
    end
  end
end

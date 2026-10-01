defmodule Mix.Tasks.GenAgentServer.Run do
  @moduledoc """
  Run an Ensemble pattern from a JSON spec in a fresh local application.

      mix gen_agent_server.run SPEC.json --prompt "Review lib/foo.ex" [--prompt ...]
          [--cwd DIR] [--to ROUTE] [--timeout MS] [--json]

  `SPEC.json` is described in `GenAgentServer.PatternSpec`. Prompts can also
  be read from a file with `--prompts-file FILE` (one prompt per non-empty
  line). `--cwd` defaults to the current directory. Exits non-zero if any
  prompt did not complete.
  """
  @shortdoc "Run an Ensemble pattern from a JSON spec"
  use Mix.Task

  @switches [
    prompt: :keep,
    prompts_file: :string,
    cwd: :string,
    to: :string,
    timeout: :integer,
    json: :boolean
  ]

  @impl true
  def run(argv) do
    {opts, args, invalid} = OptionParser.parse(argv, strict: @switches)

    if invalid != [], do: Mix.raise("invalid options: #{inspect(invalid)}")

    spec_path =
      case args do
        [path] -> path
        _ -> Mix.raise("usage: mix gen_agent_server.run SPEC.json --prompt TEXT [--json]")
      end

    spec = spec_path |> File.read!() |> Jason.decode!()
    prompts = prompts(opts)
    if prompts == [], do: Mix.raise("at least one --prompt or --prompts-file is required")

    Mix.Task.run("app.start")

    run_opts =
      [cwd: Path.expand(Keyword.get(opts, :cwd, File.cwd!()))]
      |> maybe_put(:to, opts[:to])
      |> maybe_put(:timeout, opts[:timeout])

    case GenAgentServer.Run.run(spec, prompts, run_opts) do
      {:ok, report} ->
        if opts[:json], do: IO.puts(Jason.encode!(report, pretty: true)), else: print(report)

        unless Enum.all?(report.results, &(&1.status == :completed)) do
          exit({:shutdown, 1})
        end

      {:error, reason} ->
        Mix.raise("run failed: #{inspect(reason)}")
    end
  end

  defp prompts(opts) do
    from_file =
      case opts[:prompts_file] do
        nil ->
          []

        path ->
          path
          |> File.read!()
          |> String.split("\n")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))
      end

    Keyword.get_values(opts, :prompt) ++ from_file
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp print(report) do
    IO.puts(
      "pattern #{report.pattern}, #{length(report.results)} prompt(s), #{report.elapsed_ms} ms"
    )

    report.results
    |> Enum.with_index(1)
    |> Enum.each(fn {item, i} ->
      IO.puts("\n== [#{i}] #{item.status} after #{item.elapsed_ms} ms (#{item.route})")
      IO.puts(item.text || item.error || "")
    end)
  end
end

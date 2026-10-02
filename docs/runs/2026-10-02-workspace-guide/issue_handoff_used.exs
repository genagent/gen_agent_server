# Run with:
#   mix run examples/issue_handoff.exs CONFIG.json
#
# Triage, implement, and review one issue in an isolated checkout, keeping
# every stage's output. Each stage is a separate invocation on one managed
# Switchboard instance, so the caller sees the triage plan and the
# implementer's report as well as the final review (a Pipeline returns only
# its last stage). The diff is captured with git outside any model response.
#
# CONFIG.json:
#
#   {
#     "project": "/path/to/fresh/clone",          # writable checkout for this issue
#     "issue": "path/to/issue.md",                # issue text (relative to CONFIG)
#     "instructions": "path/to/notes.md",         # optional caller constraints
#     "out": "path/to/artifacts",                 # where stage outputs are written
#     "timeout_ms": 1200000,                      # per stage (default 20 minutes)
#     "review_only": false,                       # true: re-review the current diff,
#                                                 # reusing triage.md and implement.md
#     "revise": false,                            # true: one revise round: the implement
#                                                 # stage receives review.md and edits the
#                                                 # existing diff, then a fresh review runs
#     "stages": {
#       "triage":    {"provider": "codex",  "model": null},
#       "implement": {"provider": "claude", "model": "sonnet"},
#       "review":    {"provider": "codex",  "model": null}
#     }
#   }
#
# Permissions: triage and review are read-only (Claude plan mode, Codex
# read-only sandbox). Only the implement stage can write: Claude
# accept_edits or Codex workspace_write, scoped to "project". A null model
# uses the provider CLI's configured default; the model actually used is
# read back from the CLI's local session file and recorded in summary.json.
#
# Completion: every stage returns a terminal result or the script stops. The
# script never commits, pushes, or accepts the review; the caller runs the
# package checks and decides.

defmodule IssueHandoff do
  alias GenAgentServer.{Agents, Providers}

  def main([config_path]) do
    :io.setopts(:standard_io, encoding: :unicode)
    base = Path.dirname(Path.expand(config_path))
    config = config_path |> File.read!() |> Jason.decode!()

    project = Path.expand(Map.fetch!(config, "project"), base)
    out = Path.expand(Map.fetch!(config, "out"), base)
    issue = File.read!(Path.expand(Map.fetch!(config, "issue"), base))

    notes =
      case config["instructions"] do
        nil -> ""
        path -> File.read!(Path.expand(path, base))
      end

    timeout = Map.get(config, "timeout_ms", 1_200_000)
    stages = Map.fetch!(config, "stages")
    File.mkdir_p!(out)

    unless config["review_only"] || config["revise"] ||
             git(project, ["status", "--porcelain"]) == "" do
      raise "project checkout is not clean: #{project}"
    end

    base_commit = git(project, ["rev-parse", "HEAD"])
    name = "handoff/#{System.unique_integer([:positive])}"
    agents = Enum.map(~w(triage implement review), &agent_spec(&1, stages[&1], project))
    {:ok, _} = GenAgentServer.start_instance(name, agents, max_in_flight: 1)

    try do
      review_only? = Map.get(config, "review_only", false)
      revise? = Map.get(config, "revise", false)
      prior_review = if revise?, do: archive_review(out), else: nil

      triage =
        if review_only? or revise?,
          do: reused(out, "triage"),
          else:
            run_stage(name, "triage", stages, timeout, """
            #{issue}

            #{notes}

            Task: re-check this issue against the current code in this repository. Do not edit
            files. Report which claims still hold (with file:line), which are already resolved,
            and a short, concrete plan for the smallest change that resolves the rest: files to
            edit and what each edit says or does. Do not narrate what you are about to do.
            """)

      implement =
        cond do
          review_only? ->
            reused(out, "implement")

          revise? ->
            run_stage(name, "implement", stages, timeout, """
            #{issue}

            #{notes}

            You made a change in this repository for the issue above. An independent reviewer
            requested changes. Verify each finding against the code; address the ones that hold,
            and say why for any you leave. Keep the rest of the change. Do not commit, create
            branches, push, or run network commands. Reply with the files changed and one line
            per finding: fixed, or not fixed with the reason.

            Review:
            #{prior_review}
            """)

          true ->
            run_stage(name, "implement", stages, timeout, """
            #{issue}

            #{notes}

            Triage plan from another engineer (verify it before relying on it):

            #{triage.text}

            Task: make the change in this repository. Edit only files the plan or issue requires.
            Do not commit, create branches, push, or run network commands. When done, reply with
            the files changed and one line per change.
            """)
        end

      # Intent-to-add puts new files in the diff without staging their content.
      git(project, ["add", "--intent-to-add", "--all"])
      diff = git(project, ["diff", "--stat"]) <> "\n\n" <> git(project, ["diff"])
      untracked = git(project, ["ls-files", "--others", "--exclude-standard"])

      review =
        run_stage(name, "review", stages, timeout, """
        #{issue}

        #{notes}

        An engineer made the change below for this issue, under the constraints above. Their report is not evidence; read
        the files and code yourself. Check every factual claim the change adds against the
        code, check that it resolves the issue, and check scope.

        Reply with APPROVE or REQUEST CHANGES on the first line, then findings with file:line.

        Implementer report:
        #{implement.text}

        Diff:
        #{diff}

        Untracked files:
        #{if untracked == "", do: "(none)", else: untracked}
        """)

      write(out, "triage.md", triage.text)
      write(out, "implement.md", implement.text)
      write(out, "diff.patch", diff)
      write(out, "review.md", review.text)

      summary = %{
        project: project,
        base_commit: base_commit,
        instance: name,
        verdict: verdict(review.text),
        changed_files: git(project, ["diff", "--name-only"]) |> String.split("\n", trim: true),
        untracked_files: String.split(untracked, "\n", trim: true),
        stages: Map.new([triage, implement, review], &{&1.stage, Map.delete(&1, :text)})
      }

      write(out, "summary.json", Jason.encode!(summary, pretty: true))
      IO.puts(Jason.encode!(summary, pretty: true))
    after
      GenAgentServer.stop_instance(name)
    end
  end

  # revise keeps the previous review as review-round-N.md and feeds its text
  # to the implement stage.
  defp archive_review(out) do
    text = File.read!(Path.join(out, "review.md"))
    n = Path.wildcard(Path.join(out, "review-round-*.md")) |> length() |> Kernel.+(1)
    File.write!(Path.join(out, "review-round-#{n}.md"), text)
    text
  end

  # review_only re-reviews the current diff and keeps the earlier stage text.
  defp reused(out, stage) do
    text =
      case File.read(Path.join(out, "#{stage}.md")) do
        {:ok, text} -> text
        {:error, _} -> "(not available)"
      end

    %{
      stage: stage,
      provider: nil,
      requested_model: nil,
      model: nil,
      session_id: nil,
      usage: nil,
      elapsed_ms: 0,
      reused: true,
      text: text
    }
  end

  defp agent_spec(stage, %{"provider" => provider} = conf, project) do
    edit_opts =
      case {stage, provider} do
        {"implement", "claude"} -> [claude_permission_mode: :accept_edits]
        {"implement", "codex"} -> [codex_sandbox: :workspace_write]
        _ -> []
      end

    opts = [cwd: project] ++ edit_opts ++ if(conf["model"], do: [model: conf["model"]], else: [])
    {:ok, backend_opts} = Providers.backend_opts(provider, opts)
    {stage, Agents.Role, backend_opts}
  end

  defp run_stage(name, stage, stages, timeout, prompt) do
    started = System.monotonic_time(:millisecond)
    provider = stages[stage]["provider"]

    case GenAgentServer.ask_instance(name, stage, prompt, timeout: timeout) do
      {:ok, response} ->
        %{
          stage: stage,
          provider: provider,
          requested_model: stages[stage]["model"],
          model: model_used(provider, response.session_id),
          session_id: response.session_id,
          usage: response.usage,
          elapsed_ms: System.monotonic_time(:millisecond) - started,
          text: response.text
        }

      {:error, reason} ->
        raise "#{stage} stage failed: #{inspect(reason)}"
    end
  end

  # Neither CLI backend reports the model in GenAgent events, so read it from
  # the CLI's own session file.
  defp model_used(_provider, nil), do: nil

  defp model_used("claude", session_id) do
    "~/.claude/projects/*/#{session_id}.jsonl" |> Path.expand() |> Path.wildcard() |> last_model()
  end

  defp model_used("codex", session_id) do
    "~/.codex/sessions/**/*#{session_id}*.jsonl"
    |> Path.expand()
    |> Path.wildcard()
    |> last_model()
  end

  defp model_used(_provider, _session_id), do: nil

  defp last_model([path | _]) do
    ~r/"model"\s*:\s*"([^"]+)"/
    |> Regex.scan(File.read!(path))
    |> List.last()
    |> case do
      [_, model] -> model
      nil -> nil
    end
  end

  defp last_model([]), do: nil

  # Codex can precede the verdict line with progress commentary, so find the
  # line rather than taking the first one.
  defp verdict(text) do
    Enum.find_value(String.split(text, "\n"), "missing", fn line ->
      case Regex.run(~r/^\W*(APPROVE|REQUEST CHANGES)\b/, String.trim(line)) do
        [_, verdict] -> verdict
        nil -> nil
      end
    end)
  end

  defp git(dir, args) do
    {out, 0} = System.cmd("git", ["-C", dir | args], stderr_to_stdout: true)
    String.trim(out)
  end

  defp write(dir, file, content), do: File.write!(Path.join(dir, file), content)
end

IssueHandoff.main(System.argv())

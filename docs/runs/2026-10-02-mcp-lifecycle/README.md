# MCP lifecycle and model-selection probe

The control program was [`examples/issue_handoff.exs`](../../../examples/issue_handoff.exs)
with [the exact handoff config](handoff.json), [task](task.md), and
[instructions](notes.md). It ran sequential Codex `gpt-6-astra` triage, Claude
`sonnet` implementation, and Codex `gpt-6-astra` review in one named server
instance. The [stage outputs](summary.json) and individual `triage`,
`implement`, and `review` JSON/Markdown files are retained here. The first
review requested a compiler-warning fix, a reserved-name assertion fix, and
formatting. The host made those changes and ran the checks outside the worker.
The [final review config](final-review-config.json) and
[instructions](final-review-notes.md) produced a read-only review-only approval.
It caught one README sentence that conflated instance and route names; the
host corrected the wording.

The [literal live probe](live-probe.exs) connected to the packaged release's
stdio MCP entry point. It created `model-probe` with a Codex `gpt-6-luna` route
at low effort and a Claude `haiku` route at low effort, each in the same
project directory, asked both to `Reply with exactly READY and nothing else.`,
and stopped the instance. Both returned `READY`. The provider session files
reported `gpt-6-luna` and `claude-haiku-4-5-20251001`, respectively. The
packaged Echo lifecycle smoke also passed, including discovery instructions,
the quickstart resource, create/describe/ask/stop, and invalid config checks.

The first live Claude route used plan mode and requested Haiku; its session file
instead reported `claude-sonnet-5-5`. A direct CLI probe with `dontAsk` and a
Read/Grep/Glob tool list honored Haiku. Dynamic routes now default to that
limited-tool mode, while `plan` remains explicit and static startup profiles
retain their prior default. This is a CLI behavior finding, not a claim that
provider permission flags enforce a filesystem boundary. The choice and its
limits are visible in the MCP guide and README.

The host's final local gates were format, warnings-as-errors compilation, 83
tests, release build, packaged MCP smoke, and `git diff --check`. This run
distinguishes requested models from actual session models and preserves the
client control code separately from worker outputs.

# Core test assertions and registered-agent listing

On 2026-10-02, two independent `gen_agent` issues were claimed with
`status/in-progress` and run through two named `gen_agent_server` instances
in clean clones at `abb0338`. Each used read-only triage, one writable
implementation stage, read-only review, and automatic instance cleanup. The
exact [control code](issue_handoff_used.exs), issue text, caller notes,
configs, stage text and metadata, captured diffs, and summaries are retained
in the [#110](110) and [#256](256) folders. The caller, not the model stages,
ran package checks and managed Git, PRs, CI, and labels.

## Core #110: tests assert the behavior they name

[Issue #110](https://github.com/genagent/gen_agent/issues/110) used Codex
`gpt-6-astra` for triage and review (CLI default) and Claude
`claude-sonnet-5-5` for implementation (requested `sonnet`). Sessions and
elapsed times are in [summary.json](110/summary.json). The triage found that
one of eight review findings, the Checkpointer assertion, had already been
fixed on current main. The implementation changed only the remaining tests:
callback-order state, actual backend prompt, generated macro defaults,
monotonic timestamp bounds, and a misleading error-handler test name; it
deleted the placeholder test. The independent reviewer approved, but could
not run tests before dependencies were fetched. The caller fetched locked
dependencies, then ran 91 focused and 324 full root tests, formatting,
warnings-as-errors compilation, strict Credo, and docs with warnings-as-errors.
[Core PR #355](https://github.com/genagent/gen_agent/pull/355) passed CI and merged as `80c44d7`. Issue #110 closed, and its in-progress label was removed.

## Core #256: list running agents

[Issue #256](https://github.com/genagent/gen_agent/issues/256) used Codex
`gpt-6-astra` for triage and implementation (CLI default), then Claude
`claude-sonnet-5-5` for review (requested `sonnet`). The implementation added
`GenAgent.list/0` as an unordered registry snapshot and covered registered,
unregistered, non-string, and stopped names. The reviewer approved from
source inspection without running tests. The caller fetched locked
dependencies and ran 324 full root tests, formatting, warnings-as-errors
compilation, strict Credo, docs with warnings-as-errors, and Dialyzer.
[Core PR #354](https://github.com/genagent/gen_agent/pull/354) passed CI and merged as `ff8c3c2`. Issue #256 closed, and its in-progress label was removed.

The useful control pattern here is a two-lane issue pool with a different
implementation provider on each lane, one shared handoff script, independent
review, and host-side acceptance gates. Triage was valuable because it
removed a stale finding before implementation. Both reviewers correctly
separated their source verdicts from tests they had not run. The staged
runner retained model and session metadata; those observations, rather than
requested aliases, identify the models actually used. No server mechanical
failure was observed in these runs.

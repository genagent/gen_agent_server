# Migration dependency and Supervisor guide runs

Two independent core documentation issues were claimed with `status/in-progress`
and run in separate clean clones from `0a970d4`. Each used a named
`gen_agent_server` staged handoff: read-only triage, one writable implement
stage, and read-only review. The exact issue text, caller constraints, configs,
stage reports, metadata, and [control script](issue_handoff_used.exs) are
retained here. The script stopped each managed instance; the caller owned
Mix verification, Git, PRs, CI, and issue labels. Both clones used local
fixture backends in tests, not live provider credentials.

## Core #231: consumer dependency recipes

The [issue](231/gen_agent_issue_231.md), [initial constraints](231/gen_agent_issue_231_notes.md),
and [config](231/gen_agent_issue_231_config.json) sent triage to Codex
`gpt-6-luna`, implementation to Claude `claude-sonnet-5-5`, and review to
Codex `gpt-6-astra`. The first [review](231/review-round-1.md) rejected an
incorrect description of the sparse-checkout failure and asked for a
behavioral Mix fixture. The caller verified the real checkout behavior with
Mix 1.20.4 and local `file://` Git dependencies: full `subdir` compiled from
source without `GEN_AGENT_HEX`; sparse with `GEN_AGENT_HEX=1` compiled against
published core 0.6.2; sparse without it fetched dependencies but failed at
compile time. Those facts went into the [revision constraints](231/gen_agent_issue_231_revision_notes.md)
and [revision config](231/gen_agent_issue_231_revise_config.json). The final
[review](231/review.md) approved the docs and an offline test that builds a
small local monorepo and exercises the four consumer paths. It noted one
non-blocking version reference, which the caller corrected before validation.

The focused fixture passed four tests; the full core suite passed 299 tests.
Format, strict Credo, docs, and CI passed. [PR #350](https://github.com/genagent/gen_agent/pull/350)
merged as `3d61ebf`; issue #231 closed and its in-progress label was removed.
The fixture uses a local stand-in for published Hex core so it can run offline;
the separate real-package probe checked the published dependency branch.

`revise` retained the first review text but overwrote the initial implement
report and metadata. The [latest summary](231/summary.json) therefore records
the revised implementation and review; [triage metadata](231/triage.json)
preserves the initial actual model and session.

## Core #236: Supervisor callback recipe and Research terminal phases

The [issue](236/gen_agent_issue_236.md), [initial constraints](236/gen_agent_issue_236_notes.md),
and [config](236/gen_agent_issue_236_config.json) routed triage to Claude
`claude-opus-5-5`, implementation to Codex `gpt-6-astra`, and review to
Claude `claude-opus-5-5`. Triage confirmed the five reported failures. It
also wrote a private plan file outside this run record; the retained
[triage](236/triage.md) has the external path redacted. The first
[review](236/review-round-1.md) found that a queued user turn could be
mistaken for synthesis. The [first revision](236/gen_agent_issue_236_revision_notes.md)
used `pre_turn/2` to identify the actual synthesis prompt and added a
deterministic in-flight/queued-turn test. The first review is duplicated
as [round 2](236/review-round-2.md) because both the caller and `revise`
archived it. The [second review](236/review-round-3.md) found that a rejected
synthesis prompt could leave the coordinator stuck. The
[second revision](236/gen_agent_issue_236_revision_2_notes.md) made
that rejection terminal and tested worker cleanup. The third
[review](236/review-round-4.md) approved with a non-blocking observation:
the overload handler also matched a provider overload from an unrelated
user turn. The caller narrowed the match to the server queue error shape,
added a provider-overload variant of the queued-turn test, and ran a
[final review-only pass](236/gen_agent_issue_236_final_review_config.json)
with the [exact notes](236/gen_agent_issue_236_final_review_notes.md).
The [final review](236/review.md) approved. The latest
[summary](236/summary.json) retains the final review metadata; earlier
stage metadata was overwritten by `revise` and `review_only`. The review
round texts preserve each finding. [Stage-attempt metadata](236/stage-attempts.md)
records the actual model and session ID from each handoff result before it
was overwritten.

The callback guide now uses a configurable worker backend, an OTP watcher
that monitors and stops workers, a collection deadline, per-run names,
and a synthesis-turn gate. The Research guide handles extra turns after
resuming terminal phases. Tests compile the actual code blocks and cover
worker death, dropped reports, startup failure, deadline, same-name rerun,
queued turns, internal queue overload, provider overload, and cleanup.
The caller ran 20 focused and 315 full core tests, format, strict Credo,
docs, and diff checks. After rebasing on #350, the combined 319-test suite
and quality gates passed. [PR #351](https://github.com/genagent/gen_agent/pull/351)
passed CI and merged as `e44ab6b`; issue #236 closed and its in-progress
label was removed.

The review rounds caught behavioral failures that the initial focused tests
missed. This is source correctness and test design, not a need for more
prompt wording. The control gap is separate: `revise` overwrites earlier
implementation reports and metadata, and manually copying review text
before a revision can duplicate it when the runner also archives it.
Persist every stage attempt with a monotonic round ID in a future control
API. Keep host tests, reviewer verdict, CI, and publication as separate gates.

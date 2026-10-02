# Debate and Heartbeat/Watcher guide runs

Two named, independent `gen_agent_server` handoffs ran concurrently in clean
core clones at `26bd542`, each with one stage in flight. The exact
[control script](issue_handoff_used.exs), issue text, constraints, and JSON
configs are retained here. Triage and review were read-only; only each
implement stage could edit its own clone. The script captured the diff before
review, saved stage text and metadata, and stopped each instance in `after`.
The caller ran tests, lint, docs, Git checks, PR operations, and CI outside
model responses. No real backend credential was used in guide tests.
Copied issue and review text received whitespace-only cleanup for Git checks.

## Debate, core #238

The [issue](debate/gen_agent_issue_238.md), [constraints](debate/gen_agent_issue_238_notes.md),
and [first config](debate/gen_agent_issue_238_config.json) routed triage to
Codex `gpt-6-luna`, implementation to Claude `claude-sonnet-5-5`, and review
to Codex `gpt-6-astra`. [Triage](debate/triage.md) verified the final-statement,
error-stall, and transcript claims against the guide. The first
[review](debate/review-round-1.md) requested runtime halt assertions and
formatting. The second [review](debate/review-round-2.md) reproduced a stale
completion-message bug when two debates ran in one caller process. Two bounded
[revision passes](debate/gen_agent_issue_238_revise_config.json) fixed those
issues, and the [final review](debate/review.md) approved. The latest
[summary](debate/summary.json) and per-stage JSON files record actual models,
sessions, usage, and elapsed time. Revision mode overwrote the earlier
implementation report and review metadata; their review texts remain, but
that metadata was not reconstructed.

The caller ran five focused and 285 full core tests, formatting, strict Credo,
docs, and diff checks after the final revision. [PR #348](https://github.com/genagent/gen_agent/pull/348)
passed CI and merged as `0cf996e`; issue #238 closed.

## Heartbeat and Watcher, core #244

The [issue](heartbeat-watcher/gen_agent_issue_244.md), [constraints](heartbeat-watcher/gen_agent_issue_244_notes.md),
and [first config](heartbeat-watcher/gen_agent_issue_244_config.json) routed
triage to Claude `claude-sonnet-5-5`, implementation to Codex `gpt-6-astra`,
and initial review to Claude `claude-opus-5-5`. Triage verified dropped
Heartbeat batches, missing Watcher failure records, stale notification advice,
and the ticker lifetime problem. The first four [review rounds](heartbeat-watcher/review-round-1.md)
through [round four](heartbeat-watcher/review-round-4.md) found real gaps:
private runtime-message use, stale prose, direct-prompt misattribution, and
unsupported advice for event-driven agents. The fifth
[review](heartbeat-watcher/review-round-5.md) identified a ticker name-reuse
race. The caller changed ticker pulses to carry the monitored PID; the agent
ignores a pulse intended for an earlier incarnation. A deterministic test
sends that stale pulse to a replacement. The [final review](heartbeat-watcher/review.md),
routed through the [Codex review config](heartbeat-watcher/gen_agent_issue_244_final_review_config.json),
approved the source and ten focused tests. Per-round review JSON and the latest
[summary](heartbeat-watcher/summary.json) retain requested and actual model
metadata. Review-only mode overwrote the latest `review.md`, so each prior
round was copied before the next call; implementation text and metadata from
the first run remain.

The caller ran ten focused and 290 full core tests, formatting, strict Credo,
docs, and diff checks. After rebasing onto merged #348, the combined full
suite passed 295 tests. [PR #349](https://github.com/genagent/gen_agent/pull/349)
contains the guide and test changes. The older Heartbeat and Watcher scenario
files remain as topology fixtures; the new guide tests compile the copyable
modules themselves. Supervisor scenario drift and leaked workers remain in
[core #236](https://github.com/genagent/gen_agent/issues/236).

The two runs exposed a useful control boundary: stage artifact persistence
works on a successful first pass, but `revise` overwrites the earlier
implementation report and `review_only` overwrites the last review unless
the caller archives them. Repeated reviews surfaced mechanical source gaps,
not just prompt wording. Keep durable stage histories in control code; keep
task-specific API and lifecycle decisions in the caller's review and tests.

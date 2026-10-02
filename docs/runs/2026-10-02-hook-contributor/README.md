# Hook blocking and contributor documentation runs

Two unclaimed core documentation issues were marked `status/in-progress` and
run in independent clean clones at `e44ab6b`. Each used the server's staged
issue handoff: read-only triage, one writable implementation stage, and
read-only review. The exact [control script](issue_handoff_used.exs), issue
text, caller constraints, configs, stage reports, and review rounds are
retained here. The script stopped each named managed instance after its
stages; the caller owned tests, package checks, Git, PRs, CI, and labels.
The [stage-attempt list](stage-attempts.md) preserves requested and actual
models and session IDs before `revise` or `review_only` overwrote metadata.

## Core #230: lifecycle hook blocking

The [issue](230/gen_agent_issue_230.md) and [initial config](230/gen_agent_issue_230_config.json)
routed triage to Codex Luna, implementation to Claude Sonnet, and review to
Codex Astra. The first [review](230/review-round-1.md) found the execution
table omitted backend `checkpoint_session/2`, which runs in the agent
process even when requested by a prompt task. The [revision](230/gen_agent_issue_230_revise_config.json)
added it, but the [second review](230/review-round-2.md) caught an incorrect
claim that crash recovery invokes checkpoint restoration. The caller
corrected the returned-success/error versus crash distinction and used a
[review-only pass](230/gen_agent_issue_230_final_review_config.json).
The [third review](230/review-round-3.md) asked for every named synchronous
API in both hook tests. The caller added `poll`, `tell`, and `notify_ack` to
the gated `pre_turn` case and `poll` to `pre_run`, then ran a second
[review-only pass](230/gen_agent_issue_230_final_2_review_config.json).
The [final review](230/review.md) approved.

The caller ran two focused and 321 full root tests, format, strict Credo,
docs with warnings-as-errors, and diff checks. [Core PR #353](https://github.com/genagent/gen_agent/pull/353)
passed CI and merged as `abb0338`; issue #230 closed and its in-progress
label was removed.

## Core #232: monorepo contributor guide

The [issue](232/gen_agent_issue_232.md) and [initial config](232/gen_agent_issue_232_config.json)
routed triage and review to Codex Luna and implementation to Claude Haiku.
The first [review](232/review-round-1.md) separated PR-title validation
from Release Please's use of commit history. The [revision](232/gen_agent_issue_232_revise_config.json)
made that split but said commit scope selects the released package. The
[second review](232/review-round-2.md) corrected that: changed paths select
packages. Host `mix docs --warnings-as-errors` then caught a README relative
link to the new guide, which ExDoc does not package. The caller linked to
the GitHub guide and named `scripts/quality.sh` directly in README. The
[final review](232/review.md) approved the guide and release wording.

The caller ran docs with warnings-as-errors, three PR-title validator tests,
and diff checks. [Core PR #352](https://github.com/genagent/gen_agent/pull/352)
passed CI and merged as `5a5cc90`; issue #232 closed and its in-progress
label was removed.

The observed pattern is a useful split: reviewer source inspection caught
callback-location and release-policy claims, while host execution caught
the ExDoc link warning and proved the hook blocking behavior. Neither a
model verdict nor a passing syntax check covers the other. The server
retained all successful stage texts, but `revise` replaced earlier
implementation metadata and `review_only` replaced the preceding review;
the caller archived review texts before review-only passes. An optional
control API should keep append-only stage attempts while leaving the
package checks and PR decision with the caller.

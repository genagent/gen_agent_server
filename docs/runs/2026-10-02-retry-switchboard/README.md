# Retry and Switchboard guide issue runs

Two named staged handoffs ran concurrently through `gen_agent_server`, each
in a clean clone at core commit `e9920af`, with at most one stage in flight
per instance. The [literal control script](issue_handoff_used.exs) is the
version merged by [server PR #59](https://github.com/genagent/gen_agent_server/pull/59):
it saves a completed stage's text and model/session metadata before starting
the next stage, saves the diff before review, and records terminal stage
errors. The first triage files appeared while both implementation stages
were still active, confirming this boundary in live use. Each invocation
stopped its named instance in the script's `after` block. The caller owned
source validation, commits, CI, and merge decisions.

## Retry, core #241

The [issue](retry/gen_agent_issue_241.md), [original constraints](retry/gen_agent_issue_241_notes.md),
and [first configuration](retry/gen_agent_issue_241_config.json) used Codex
`gpt-6-luna` triage, Claude `claude-sonnet-5-5` implementation, and Codex
`gpt-6-astra` review. The first reviewer [requested changes](retry/review-round-1.md):
interrupt during idle backoff does not cancel a timer, and the tests did not
prove delay progression or stale-token delivery. The caller independently
ran 11 focused tests, strict Credo and docs, and confirmed that formatting
failed. The [revision constraints](retry/gen_agent_issue_241_revision_notes.md)
and [revision config](retry/gen_agent_issue_241_revise_config.json) fed those
findings to one Claude revision and Codex re-review. The second
[review](retry/review-round-2.md) still found formatting and overlapping
timing ranges. The caller fixed those narrowly: the local backend stamps
prompt start time, and the assertions require increasing gaps that a constant
delay cannot satisfy. The caller formatted the test, then ran 13 focused and
273 full core tests, strict Credo, docs with warnings as errors, and diff
checks. A [final review-only pass](retry/gen_agent_issue_241_final_review_config.json)
[approved](retry/review.md) the final diff.

The [latest summary](retry/summary.json), [triage](retry/triage.md),
[latest implementation report](retry/implement.md), stage metadata JSON files,
and two earlier review rounds are retained. The revision mode overwrote the
first implementation report and metadata; the [original report](retry/initial-implement.md)
was recovered from that Claude session's final text, and the
[original metadata](retry/initial-implement-metadata.json) and
[first review metadata](retry/initial-review-metadata.json) were retained
from the first control summary. This overwrite is another concrete artifact
retention boundary for the optional control API. The source fix is
[gen_agent PR #347](https://github.com/genagent/gen_agent/pull/347),
which passed CI and merged as `26bd542`.

## Switchboard, core #237

The [issue and added findings](switchboard/gen_agent_issue_237.md),
[constraints](switchboard/gen_agent_issue_237_notes.md), and
[configuration](switchboard/gen_agent_issue_237_config.json) used Claude
`claude-opus-5-5` triage, Codex `gpt-6-astra` implementation, and Claude
`claude-sonnet-5-5` review. The [review](switchboard/review.md) approved from
source and ran 7 focused tests; the caller ran the 7 focused tests and full
267-test core suite, formatting, strict Credo, docs with warnings as errors,
and diff checks. The reviewer noticed one stale sentence in the guide's
module documentation; the caller corrected it and rebuilt docs. The
[summary](switchboard/summary.json), [triage](switchboard/triage.md),
[implementation report](switchboard/implement.md), and per-stage JSON files
retain the requested and actual models, sessions, usage, and elapsed times.
The triage text's local home-directory plan path was redacted; its findings
and plan remain in that stage output.
The source fix is [gen_agent PR #346](https://github.com/genagent/gen_agent/pull/346),
which passed CI and merged as `328740c`.

The stages and host checks remain separate evidence. Review approval did not
stand in for executable tests; the Retry reviewer found a behavioral gap that
the first passing test suite missed. The successful stage-boundary write
belongs in control code, while how an agent describes an interrupt or
decomposes a guide remains behavioral guidance.

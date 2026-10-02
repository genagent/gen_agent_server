# Claude backend option validation (#117)

[Issue #117](https://github.com/genagent/gen_agent/issues/117) was claimed with
`status/in-progress` before work. A fresh clone at core commit `46ce54f`
(`/tmp/gen_agent_claude_options_117`) held the only source edits; the user's
`chore/core-refresh` checkout and its existing changes were untouched. The
server control program was [`examples/issue_handoff.exs`](../../../examples/issue_handoff.exs)
from server commit `84cf150`. It ran one named Switchboard instance per pass,
with separate triage, implementation, and review invocations, then stopped the
instance. No server worker committed or pushed code.

The exact task text is [issue.md](issue.md). Caller instructions at each pass
are [initial-notes.md](initial-notes.md),
[revision-notes.md](revision-notes.md), and [notes.md](notes.md). The matching
[initial](initial-config.json), [revision](revision-config.json), and
[final](final-config.json) configs record project and artifact paths, the
15-minute per-stage limit, provider/model choices, and the `revise` or
`review_only` switch.
Each pass ran `MIX_ENV=prod mix run examples/issue_handoff.exs
/tmp/gen_agent_issue_117_handoff.json`. The code generated the exact stage
prompts by combining the issue and instructions with its checked-in triage,
implement, and review templates. No custom shell prompt or client config was
used.

| Stage | Requested / observed model | Evidence |
| --- | --- | --- |
| Triage | Codex `gpt-6-luna` / `gpt-6-luna` | [triage.md](triage.md) confirmed startup and silent-drop paths on current source. |
| Initial implementation | Claude `sonnet` / `claude-sonnet-5-5` | Initial adapter and tests were written; model could not run Mix under its tool boundary. |
| Review 1 | Codex `gpt-6-astra` / `gpt-6-astra` | [review-round-1.md](review-round-1.md) requested compatibility fixes for environment, `no_session_persistence: false`, and the incomplete option list. |
| Revision | Claude `sonnet` / `claude-sonnet-5-5` | [implement.md](implement.md) and source diff expanded coverage to every locked wrapper option. |
| Review 2 | Codex `gpt-6-astra` / `gpt-6-astra` | [review-round-2.md](review-round-2.md) found valid `ToolPattern` entries rejected and struct-shaped environment input able to raise. |
| Final review | Codex `gpt-6-astra` / `gpt-6-astra` | After host corrections, [review.md](review.md) approved the current diff with no actionable findings. |

The host fetched the locked dependencies and ran checks outside model
responses. The first focused run failed 1 of 19 tests because
`no_session_persistence: false` had been rejected. After revision, 21 focused
and 79 full tests passed. The host then fixed the review-2 findings and added
regressions. The final Claude adapter suite passed **80 tests** (3 tagged live
tests excluded); format, warnings-as-errors compile, strict Credo, Dialyzer,
and docs all passed. A source comparison confirmed that all 51
`ClaudeWrapper.Query.apply_opt/2` keys in locked wrapper 0.14.5 remained
accepted. [Core PR #373](https://github.com/genagent/gen_agent/pull/373)
passed every PR CI gate, including Hex archive builds, and merged as
`158765c`. Issue #117 closed and its `status/in-progress` claim was removed.
The adapter Hex release is a separate publication gate.

This run separates behavioral review from verified mechanics: model
implementation did not establish test success; the host caught the first
regression. Independent reviews found real compatibility gaps that the first
passing set of new tests missed. The final code was committed and pushed by
the host from the isolated clone, and no managed Switchboard instance was
left running.

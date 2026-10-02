# Ensemble token cancellation run

This continues [the #249/#259 run](../2026-10-02-title-ensemble/README.md)
after completion and event-driven await merged as gen_agent #337. Core #259
remained claimed with `status/in-progress`. The caller cloned a clean
`gen_agent` checkout at `521f62d` and left the other session's checkouts and
PRs alone. The server control checkout had `issue_handoff.exs` from server
main `6cc57b0` (the exact [control code](issue_handoff_used.exs) is retained
here). Codex CLI was 0.157.1 and Claude Code CLI 2.1.284.

The literal [issue](gen_agent_issue_259_cancel_prompt.md),
[constraints](gen_agent_issue_259_cancel_notes.md), and
[stage config](gen_agent_issue_259_cancel_config.json) preserve the input to
the first run. The script admitted one named Switchboard with
`max_in_flight: 1`; triage and review were read-only, and only implementation
had `workspace_write` in the isolated clone. Each stage had a 20-minute
timeout. It captured the diff outside model text and stopped the instance in
`after`. It never committed, pushed, merged, or accepted the review.

| Stage | Provider and actual model | Time | Evidence |
| --- | --- | ---: | --- |
| Design/triage | Claude `claude-opus-5-5` | 115 s | Checked all seven strategy state shapes, exact child request refs, and cancellation race semantics. |
| Implement | Codex `gpt-6-astra` | 320 s | Added token-scoped cancellation, strategy callbacks, late-result fencing, and controlled tests. |
| Review 1 | Claude `claude-sonnet-5-5` | 100 s | [APPROVE](review-round-1.md) by source review; the reviewer could not run package tests. |

The caller ran 169 Ensemble tests successfully. `mix credo --strict` then
found two alias-ordering warnings and an overly complex `cancel_token/4`.
The reviewer also identified an unbounded child call in `cancel_child`.
These were mechanical gaps, not reasons to change model behavior or prompt
policy. The caller made them concrete inputs to one bounded revise round:
[revision instructions](gen_agent_issue_259_cancel_revision.md) and
[config](gen_agent_issue_259_cancel_revision_config.json). The runner archived
the first review and preserved triage while Codex revised the existing diff.

| Stage | Provider and actual model | Time | Evidence |
| --- | --- | ---: | --- |
| Revise | Codex `gpt-6-astra` | 87 s | Split the complex function, sorted aliases, and bounded each core cancellation/interrupt call to five seconds. |
| Review 2 | Claude `claude-sonnet-5-5` | 24 s | [APPROVE](review.md); ran 11 focused cancellation tests and strict Credo, but not the full suite. |

The [retained final summary](summary.json) records instance, provider
session IDs, actual models, elapsed times, and usage for the revise round.
The caller then ran the full 169 Ensemble tests, `mix format
--check-formatted`, strict Credo, Dialyzer, `mix docs
--warnings-as-errors`, and `git diff --check`; all passed. The tested change
is [gen_agent PR #339](https://github.com/genagent/gen_agent/pull/339).
Cross-package CI and the release PR are separate host gates.

The control pattern worth reusing is a two-round limit with explicit evidence:
the model review is one gate, host checks are another, and a revise stage
receives exact failing command output or a verified reliability finding.
Permission modes, timeout, artifact capture, and cleanup belong to the
server runner; the prompt chooses issue scope and expected behavior.
The issue remains open for request-ref-correlated stream forwarding after
core #106. No managed instance remained active after the terminal stage;
the isolated checkout was retained for PR validation.

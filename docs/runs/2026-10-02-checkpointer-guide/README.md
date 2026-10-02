# Checkpointer guide issue run

This run addressed [gen_agent #243](https://github.com/genagent/gen_agent/issues/243) in a clean clone at `22de093`, after claiming the issue with `status/in-progress`. The [exact issue](gen_agent_issue_243.md), [constraints](gen_agent_issue_243_notes.md), [stage config](gen_agent_issue_243_config.json), and [control code](issue_handoff_used.exs) are retained. The control checkout was at `096df91`; Codex CLI was 0.157.1 and Claude Code CLI 2.1.284. One named Switchboard ran read-only triage, an isolated writable implementation, and read-only review with `max_in_flight: 1` and a 20-minute timeout per stage. The runner stopped the instance in `after`; it did not commit, push, or accept its own review.

| Stage | Provider and actual model | Time | Evidence |
| --- | --- | ---: | --- |
| Triage | Codex `gpt-6-astra` | 64 s | [Rechecked](triage.md) notification deferral, stale review risk, and the drift between guide and scenario test. |
| Implement | Claude `claude-sonnet-5-5` | 107 s | [Added](implement.md) draft-specific review tokens, a failed-turn phase and retry, and a scenario test that compiles the guide's actual module. Claude could not run Mix checks in its edit environment. |
| Review | Codex `gpt-6-astra` | 57 s | [APPROVE](review.md) from source inspection; verified notification ordering and result-state timing but did not execute tests. |

The [summary](summary.json) retains the instance, session IDs, actual models, usage, elapsed times, and changed files. The caller independently ran 12 focused Checkpointer tests and the full 241-test core suite. Formatting, strict Credo, docs with warnings as errors, and diff checks passed. The caller also made the usage snippet's mutually exclusive review alternatives comments, so copying it sends only one decision. [gen_agent PR #344](https://github.com/genagent/gen_agent/pull/344) passed CI and merged as `e48358e`.

The control lesson is that a model's edit report and review approval do not substitute for executable checks. Here neither provider stage could run the tests, while host validation established the behavior. The protocol repair itself remains in ordinary OTP state and messages: each decision names the draft it reviewed, and a failed turn has a ref-specific retry. Stage permissions, timeout, artifact capture, and cleanup stayed in code; the prompt specified expected behavior and issue scope.

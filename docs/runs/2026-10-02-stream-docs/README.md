# Core stream API and Ensemble example runs

Two independent issues were claimed with `status/in-progress` and run in clean
`gen_agent` clones at `8f6cb9d`. A read-only Claude Opus Solo design for core
#106 and a three-stage handoff for Ensemble docs #206 ran concurrently. The
core implementation then used a separate three-stage handoff. No more than two
server instances ran at once. Claude Code CLI was 2.1.284; Codex CLI was
0.157.1. The [control code](issue_handoff_used.exs) and literal
[issue](issue-106/gen_agent_issue_106.md), [design input](issue-106/gen_agent_issue_106_design.exs),
[constraints](issue-106/gen_agent_issue_106_notes.md), and [configs](issue-106/gen_agent_issue_106_config.json)
are retained alongside stage outputs and PR links. Each temporary instance was
stopped by the runner's `after` block. The runners did not commit, push, merge,
or accept model reviews.

| Work and stage | Provider and actual model | Time | Result |
| --- | --- | ---: | --- |
| #106 read-only design | Claude `claude-opus-5-5` | 121 s | Chose an opt-in `stream_to:` recipient and task-to-agent relay for ordered deltas. [Design](issue-106/design-plan.md) and [model evidence](issue-106/design-metadata.json). |
| #106 triage | Codex `gpt-6-astra` | 86 s | Rechecked current source and planned the additive API. |
| #106 implementation | Claude `claude-sonnet-5-5` | 156 s | Added relay, ref-tagged events, lifecycle cleanup, docs, and focused tests. |
| #106 review 1 | Codex `gpt-6-astra` | 93 s | [Requested changes](issue-106/review-round-1.md): queued-halt leak, invalid test prompts, weak ordering assertions, and missing dispatch-failure coverage. |
| #106 revise | Claude `claude-sonnet-5-5` | 65 s | Addressed those findings using the [verified test failures](issue-106/gen_agent_issue_106_revision.md). |
| #106 review 2 | Codex `gpt-6-astra` | 70 s | Approved revised implementation. |
| #106 host-change review | Codex `gpt-6-astra` | 109 s | [Approved](issue-106/review.md) private relay-tag validation and test cleanup after the caller fixed them. |
| #206 triage | Claude, requested Haiku, used `claude-sonnet-5-5` | 41 s | Confirmed shipped docs referenced the test-only Mock backend. |
| #206 implementation | Codex `gpt-6-luna` | 40 s | Changed the shipped example to Echo and Simple. |
| #206 review | Claude `claude-sonnet-5-5` | 22 s | [Approved](issue-206/review.md) the model diff. |

For #106, the caller reproduced the first two review findings with the focused
suite (16/18 passed) and found one formatting failure; strict Credo passed.
After the revise round, the caller added a private per-dispatch tag so a
process with a public request ref cannot inject a fake stream event. A focused
test exposed an `on_exit` race in the unavailable-supervisor fixture; the
caller fixed that cleanup and ran the focused suite (19 passed). The final
diff passed 226 core tests, formatting, strict Credo, Dialyzer, warning-free
docs generation, and `git diff --check`. The final diff is in
[gen_agent PR #341](https://github.com/genagent/gen_agent/pull/341). The
dependent Ensemble token-streaming slice remains in core issue #259.

For #206, the caller removed a text-matching test that duplicated the existing
Echo/Simple end-to-end test, then replaced the example's immediate `:pending`
assertion with `await` followed by a retained-result poll. The exact
[example check](issue-206/example_check.exs) ran successfully. All 169
Ensemble tests, formatting, and warning-free docs generation passed. The
final diff is in [gen_agent PR #340](https://github.com/genagent/gen_agent/pull/340).
The stage reports and caller changes are described separately here.

The reusable control pattern is a bounded revise round driven by independent
review plus host test evidence, followed by a read-only review when the caller
changes the code. The server handles instance lifecycle, provider permissions,
timeouts, stage capture, and actual model lookup for handoffs. The caller still
owns issue claims, tests, PRs, and deciding what to do with a review. The
Solo `Run.run/3` report did not retain its session ID, so the caller recovered
the actual Opus model from the CLI session file; that belongs in the optional
control API. Claude plan mode again ignored a requested Haiku model and used
Sonnet. These are orchestration and provider-behavior findings, separate from
the source-level fixes.

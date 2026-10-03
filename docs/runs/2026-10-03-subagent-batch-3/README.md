# Three-fix worker batch, 2026-10-03 (third interval)

Josh authorized a 30-minute cadence with up to three independent bug fixes,
two delegated and one handled in the calling chat. At selection, the four
scoped repositories had 98 open issues: 92 in `gen_agent`, six in
`gen_agent_server`, and none in either wrapper. This remains above the
30-issue switch point, so the parent used Codex app subagents instead of
GenAgent Server as issue workers. No Claude or Codex provider call or server
worker spec was used in this batch. The delegated Codex model and effort
were inherited from the parent; neither was overridden. Core issues
[#180](https://github.com/genagent/gen_agent/issues/180),
[#184](https://github.com/genagent/gen_agent/issues/184), and
[#186](https://github.com/genagent/gen_agent/issues/186) were unassigned,
had no overlapping open PR, and were claimed with `status/in-progress`
before work. All primary checkouts and unrelated branches were preserved.

## Exact delegated instructions

The runner-selection worker received:

> Own genagent/gen_agent#180 (already claimed status/in-progress): configured Codex wrapper runner module may silently fall back to Port when unloaded or lacking stream_lines/4. Work only this fix in isolated clean worktree(s), preserving all other local changes. Reverify current wrapper 0.5.7/main behavior; add deterministic regression for unloaded module and unsupported configured module; ensure explicit error or warning per issue while preserving default runner behavior. Your code scope is codex_wrapper_ex Runner selection/config only; do not edit Port stream line framing or gen_agent event_translator because other workers own #186/#184. Run appropriate tests/checks outside model output, seek independent read-only review, push, PR, merge when green under Josh's explicit authorization, and coordinate release with me before release PR. Document exact commands, prompts, checkout, CI, failures and result for server dogfooding log. If scope overlaps, pause and message me.

The event-translation worker received:

> Own genagent/gen_agent#184 (already claimed status/in-progress): Codex event translator drops current item types and duplicates full action item maps, causing capture byte overflow. Work only this fix in isolated core worktree, preserving unrelated local changes. Reverify actual Codex wrapper/event schema current main, distinguish known schema from speculation, design nonduplicating event mapping and test every confirmed item type plus event byte behavior. Code scope integrations/codex event_translator and its tests; do not edit codex_wrapper_ex Runner or Port framing because #180/#186 are parallel. Run appropriate checks, independent read-only review, push PR, merge when green under explicit standing authorization; coordinate any release with me. Record exact prompt/spec, tests, CI, failures, cleanup for server control-pattern log. If overlap appears, pause and message me.

The parent handled #186 directly in `/private/tmp/codex_wrapper_fix_186`
and its adapter follow-up in `/private/tmp/gen_agent_fix_186`. It told the
#180 worker to keep new tests out of `runner_test.exs` because #186 needed
that file. It told #184 to avoid wrapper source and to keep Codex's existing
terminal handling of `CodexWrapper.StreamError` separate from item-level
nonfatal `error` records. These file boundaries allowed the three fixes to
run concurrently despite sharing the Codex product area.

The #180 patch received this independent read-only review request:

> Please independently review #180 proposed wrapper fix read-only at /private/tmp/codex_wrapper_fix_180 versus origin/main. Scope Runner selection only. Check unloaded-module behavior, invalid configured module, default runner compatibility, return/error stream contract, test adequacy. Do not edit, push, or post public review. Send findings to me and /root/codex_runner_180.

The #186 wrapper patch received this independent read-only review request:

> Please independently review read-only my #186 Codex wrapper patch at /private/tmp/codex_wrapper_fix_186 versus origin/main. Focus on Port :line frame semantics at exactly/over 1MiB, silent loss, typed StreamError propagation, deadline/draining branch, early termination cleanup/mailbox, test adequacy and compatibility. Do not edit/push/post public review. Report blocking/nonblocking findings with file/line or explicit clear.

The #186 adapter follow-up received this independent read-only review
request:

> Please independently review read-only the #186 consolidated-core Codex adapter follow-up at /private/tmp/gen_agent_fix_186 versus origin/main. It raises codex_wrapper floor/lock to published 0.5.8 and adds executable fake-CLI oversized-JSONL regression. Confirm it truly exercises public GenAgent failure path, no accidental fixture contamination or metadata mismatch, package/release correctness, and no unrelated changes. Do not edit/push/post public review. Report findings or clear.

## Findings and mechanical evidence

For #180, `Runner.stream_lines/4` used `function_exported?/3` without
loading the configured module, so an unloaded runner silently fell back to
Port. The worker added `Code.ensure_loaded/1` and a warning for an explicitly
configured runner that cannot stream, while keeping the default Port path.
The new test file covers a compiled module deliberately unloaded and
reloaded, a missing module, an optional callback absent, and the default.
Local checks: four focused tests, 422 wrapper tests with four integration
tests excluded, format, warnings-as-errors compile, strict Credo, and diff
check. The worker resolved an initial nested-alias test failure, a test
module that could not reload after unload, cached-Forcola version mismatch,
and local Mix TCP-lock/DNS sandbox failures. Independent review found no
blocker. Isolated branch `fix/runner-stream-dispatch-180`, commit `10c4368`,
[wrapper PR #113](https://github.com/genagent/codex_wrapper_ex/pull/113)
merged as `65e8e802f8eb80694e35ababe46311cb0276d5cb` after three CI
checks passed. Core issue #180 closed and its claim was removed. The worker
left the wrapper release to the parent for coordination.

For #184, the worker verified the nine current Codex exec item variants
against upstream `codex-rs/exec/src/exec_events.rs`; the wrapper's parser
does not impose an item schema. It now emits a compact `:tool_use` marker
when an action starts and the full item only once on completion. Reasoning,
todo-list, and nonfatal error items become activity records, separate from
a terminal turn error. A 600 KB command output remains under the default
1 MiB event-capture limit with exact coverage. An initial full-suite
failure came from a recorded fixture that expected the formerly dropped
nonfatal error item; the worker updated that assertion and reran green.
The parent independently reviewed the diff with no blocker. Targeted tests
passed 55; the full Codex suite passed 102 with three live tests excluded;
Credo and diff checks passed. Isolated branch `fix/codex-item-events-184`,
commit `860ae4d`, [core PR #386](https://github.com/genagent/gen_agent/pull/386)
merged as `c4baa01ff07070b73b19055a62968025d60c4b46` after 19 CI
checks passed. Issue #184 closed, claim removed, and the isolated checkout
was removed. The Codex release PR was held for #186's wrapper dependency.

For #186, the parent first wrote an executable wrapper test: a JSONL event
over 1 MiB was silently dropped while a later `turn.completed` survived.
The test failed against wrapper 0.5.7. `Runner.Port` now uses a line frame
one byte over its supported 1 MiB maximum to distinguish exactly 1 MiB from
oversized output. Either an over-limit `:eol` frame or an oversized
`:noeol` fragment yields a typed `{:line_too_long, 1_048_576}` error,
which `JsonLineEvent.parse_stream/1` exposes as `StreamError`; the stream
then ends. Tests cover the exact byte boundary, one byte above it, several
fragments, a producer already exited during slow consumption, and an
unterminated oversized line. An independent reviewer found a Port mailbox
cleanup edge in the first patch. The parent added failed-state cleanup for
both live and completed producers, then ran 30 focused cleanup repetitions.
The reviewer rechecked and found no blocker. Full wrapper tests, format,
warnings-as-errors compile, strict Credo, Dialyzer (zero errors), docs,
and diff checks passed after rebasing onto #180. Isolated branch
`fix/oversized-jsonl-186`, [wrapper PR #115](https://github.com/genagent/codex_wrapper_ex/pull/115)
merged as `dc141a42085c811aa55b5820a5f1ddfa546abae3` after three
CI checks passed.

Release Please [wrapper PR #114](https://github.com/genagent/codex_wrapper_ex/pull/114)
included both #180 and #186 and was merged as
`09630fed7b1eb3893d661f33c605726a8e2e8851`. Release workflow
`37134947278` succeeded, GitHub
[v0.5.8](https://github.com/genagent/codex_wrapper_ex/releases/tag/v0.5.8)
was published, and `mix hex.info codex_wrapper 0.5.8` confirmed Hex. The
release branch had a no-job CI workflow-file failure (`37134921272`),
but the three fix-PR CI jobs and post-release main CI `37134947276` passed.

The #186 adapter follow-up on `fix/codex-jsonl-floor-186` raises only the
Codex integration's wrapper dependency floor and lock to published 0.5.8.
An executable fake-CLI regression emits an oversized agent message followed
by `turn.completed` and asserts that `GenAgent.ask/2` and the failure
observer receive the typed line error. This prevents a silently dropped
message from looking like a successful empty response. The test uses a
per-test executable copy and directory. Focused executable tests passed 23;
full Codex integration passed 103 tests with three live tests excluded;
format, warnings-as-errors compile, strict Credo, Dialyzer (zero errors),
docs, and diff checks passed. Independent read-only review found no issue.
Commit `f6bacbc` is in
[core PR #388](https://github.com/genagent/gen_agent/pull/388); CI was in
progress at this log update. The Codex adapter release and closure of #186
remain pending until that PR passes.

No automated GenAgent Server issue-worker control code was created in this
batch because the backlog threshold was not reached. The reusable control
pattern is explicit ownership, file-level scope coordination across agents,
independent evidence-based review, package publication before dependency
floor changes, and a final executable consumer regression. These are
candidate inputs to the optional workflow control API in
[server #40](https://github.com/genagent/gen_agent_server/issues/40).

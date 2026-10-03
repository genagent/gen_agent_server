# Three-fix worker batch, 2026-10-03 (second interval)

Josh asked for a recurring batch of at most three independent issue fixes, with
two delegated to subagents and one handled in the calling chat. The four scoped
repos had 102 open issues at selection time: 96 in `gen_agent`, six in
`gen_agent_server`, and none in the Claude or Codex wrapper repos. This is
above the 30-issue switch point, so these were Codex app subagents rather than
GenAgent Server workers. No provider call was used by the parent. The parent
used the Codex app subagent runtime with its inherited model setting; no
model or reasoning-effort override was requested for either worker or review.
The parent did not send issue implementation through the GenAgent Server MCP
surface because the backlog threshold was not met. It checked issue details,
labels, assignees, and open PR overlap, and claimed
[#182](https://github.com/genagent/gen_agent/issues/182),
[#113](https://github.com/genagent/gen_agent/issues/113), and
[#98](https://github.com/genagent/gen_agent/issues/98) with `status/in-progress`
before work. Dirty root checkouts were left untouched; each fix used isolated
worktrees. A core retry feature draft (#331) touches `server.ex`; it did not
own #98 and this fix is based on `main`.

## Exact worker instructions

The Codex timeout worker received:

> Own genagent/gen_agent#182 (claimed status/in-progress): Codex quiet period >5 min misreported as no_terminal_event, wrapper Port/Forcola timeout mismatch. Work only this fix across core Codex backend and codex_wrapper_ex as needed, isolated worktrees; preserve dirty base checkouts and all unrelated local changes. Re-verify current main and wrapper version, design distinct idle/turn deadlines and typed error, write meaningful deterministic regression tests, run relevant checks outside model responses. Get independent read-only review (you may ask another subagent only if capacity allows; otherwise self-review with adversarial tests), push branch, create PR(s), wait CI, merge when green under standing authorization, close/clear label as appropriate. Do not overlap #113 or #98. Report exact commands/tests/branch/PR/merge and exact worker prompt/stage evidence for server dogfooding/control log. If a cross-repo release is needed, coordinate dependency order. User wants only concrete fix issues, no broad features.

The Anthropic stop-reason worker received:

> Own genagent/gen_agent#113 (claimed status/in-progress): Anthropic refusal/max_tokens/context-window stops incorrectly successful, with OpenAI incomplete and stranded user message mentioned in issue. Work only this fix in isolated worktrees; preserve dirty base checkouts and unrelated changes. Re-verify current main; design across HTTP adapters and core response shared surface only as needed, carefully decide typed terminal errors vs explicit incomplete metadata, correct session history; add deterministic regression tests; run relevant formatting/compile/tests/docs/checks outside model responses. Obtain independent read-only review if capacity permits, push branch, create PR(s), await CI, merge when green under standing authorization, close/clear label as appropriate. Avoid #182 and #98 work. Report exact prompts/stages/branches/PR/merge/test evidence for server dogfooding/control log. Keep scope to concrete fix; do not work broad feature/backlog.

The parent assigned an independent, read-only review of #98:

> Perform independent, read-only review of genagent/gen_agent#98 fix in /private/tmp/gen_agent_fix_98 compared with origin/main. Focus on correctness of Registry loss handling, supervised and direct Server cases, OTP exit semantics, races, test isolation, data leakage and regressions. Do not edit files or create PR. Report actionable findings with file/line and severity; also report if no findings. Parent is implementing and will handle changes.

The reviewer received this clarification after the implementation narrowed its
registration guard:

> One small refinement since you started: `registered` now requires the exact `{:via, Registry, {GenAgent.Registry, name}}` value rather than any non-nil registration. Focused tests remain green.

That review found no actionable issue. It verified OTP handles the parent
`EXIT` separately and that prompt-task exits retain their prior behavior. The
parent separately reviewed #113 and sent:

> I reviewed your current diff read-only. The terminal stop mapping and preserved request history look sound; core already carries the returned session through error handling, and OpenAI's current response_error covers incomplete/refusal. No blocking finding. Please consider one malformed/unknown stop test already covered by pause_turn. Continue PR/CI.

The #98 reviewer was then reused for independent read-only review of #182:

> Please perform a new independent read-only review of #182 across /private/tmp/codex_wrapper_fix_182 and /private/tmp/gen_agent_codex_fix_182 versus each origin/main. Focus on timeout semantics, silent stream ending, error propagation, process cleanup, backwards compatibility, package/dependency order, and tests. Do not edit or post public review. Send actionable findings with severity/file/line or explicit clear to /root/codex_182 and me. This is a fresh review task; do not spend time on #98 again.

After the archived adapter checkout was replaced with a consolidated-core
worktree, the parent reviewed its final diff at `0b00ec3` and sent:

> Final read-only review of consolidated PR #383 at 0b00ec3 is clear. The transplant is limited to integrations/codex, its option forwarding and StreamError translation match published wrapper 0.5.6, and executable tests cover separate idle vs whole-turn errors. I checked checkpoint_raw tolerates StreamError and Forcola nil idle disables its optional bound. No blocking finding; merge after PR CI is green.

The Anthropic worker, after finishing its fix and release, was reused as a
fresh read-only reviewer of the wrapper patch:

> Please perform a fresh independent read-only review of the Codex wrapper follow-up fix for gen_agent #182 in `/private/tmp/codex_wrapper_fix_182b` versus its origin/main. This is not Anthropic work. Focus on ordered Port mailbox draining after deadline, exits vs buffered data, early stream halt cleanup, process/resource behavior, and tests. Do not edit or post public review. Report concrete findings with severity/file/line or explicit clear to me and `/root/codex_182`. The worker is currently addressing the early-halt close_port case I found; review the latest diff when ready.

## Stage evidence and control learning

For #98, the parent first added Registry partition-crash and orderly-restart
tests; both failed on current `main` because the agents remained alive. A
first implementation stopped any server on an `EXIT` after failed Registry
lookup; the full suite found 54 regressions in deliberately unregistered
server instances. The implementation then recorded whether the server had
been started with the exact GenAgent Registry `:via` name. Focused tests passed
and the final core suite passed 337 tests. Strict Credo, formatting, docs,
diff check, and independent review passed. A third regression verified active
prompt task cancellation and caller release. The parent selected a clean
shutdown reason `{:shutdown, :registry_lost}`, which runs termination hooks
without an error log. Worktree: `/private/tmp/gen_agent_fix_98`; branch:
`fix/registry-loss-98`; commit: `2e86847`; PR:
[#382](https://github.com/genagent/gen_agent/pull/382), merged as
`9d9fa0fecc28bb994c54669aba8bea0f681b7f42` after all 19 PR checks
passed. Issue #98 closed and its claim was removed. A post-merge main run was
later confirmed successful (CI run `37125395052`).

The #182 worker initially found a separate `genagent/gen_agent_codex`
checkout and prepared adapter changes there, but a push revealed that this
repository is archived and read-only. The active adapter source is in
consolidated `gen_agent` at `integrations/codex`; the worker moved the tested
change to a new isolated core worktree and left the archived repository
untouched. The wrapper fix was merged in
[codex_wrapper_ex PR #109](https://github.com/genagent/codex_wrapper_ex/pull/109)
as `e4852d6`. Pre-PR mechanical evidence: wrapper 414 tests (four live
excluded), docs and Credo; adapter 48 tests (three live excluded) against the
exact local wrapper source, and Credo. Wrapper release 0.5.6 must publish
before the active adapter can pin `~> 0.5.6`.
Independent review found one P2 before PR: the wrapper convenience
`CodexWrapper.stream/2` path did not include `:idle_timeout_ms` in its
configuration splitter, so a per-call value would be silently ignored. The
worker added the key and a focused test. The same reviewer found a second P2:
a slow stream consumer could resume after the deadline while a successful
`exit_status` was already queued, producing a false timeout and a five-second
cleanup wait. A minimal `echo ok` reproduction confirmed it. The worker made
the Port runner drain a queued exit status first and passed 21 focused Port
tests.

The wrapper's Release Please
[#110](https://github.com/genagent/codex_wrapper_ex/pull/110) merged as
`635cc88`; release workflow `37125381013` was queued. The archived adapter
worktree `/private/tmp/gen_agent_codex_fix_182` remains clean with local
commit `e0244e0`, not pushed. The active core transplant is in
`/private/tmp/gen_agent_fix_182`.

The wrapper release workflow subsequently completed successfully. GitHub
[v0.5.6](https://github.com/genagent/codex_wrapper_ex/releases/tag/v0.5.6)
and `mix hex.info codex_wrapper 0.5.6` independently confirmed publication.
The active core Codex integration then resolved published `~> 0.5.6` (lock
0.5.5 to 0.5.6) and passed 100 tests with three live tests excluded,
formatting, and Credo.

The consolidated adapter is in
[#383](https://github.com/genagent/gen_agent/pull/383), branch
`fix/codex-stream-timeouts-182`, commit `0b00ec3`. Final local checks against
published Hex 0.5.6: 100 tests with three live excluded, formatting,
warnings-as-errors compile, strict Credo, Dialyzer, and docs. CI was still
running when the parent asked the worker to hold the merge for the new edge.
An auto-merge request had already been armed, and #383 merged as
`c0ca936ab415ea562bc0851f08f50128aeabe0d6` at
2026-10-03 13:24:38 UTC as its last gate turned green. Issue #182 remained
open and claimed; a wrapper 0.5.7 plus adapter dependency follow-up is now
required before it is complete. The parent explicitly asked that no
auto-merge be armed on the follow-up until its final review is complete.
Post-merge main CI run `37126078256` passed.

After the wrapper 0.5.6 release and adapter PR review, the parent found a
third Port deadline edge: selecting a queued `exit_status` can skip earlier
buffered output frames. A local reproduction using
`Port.stream_lines("sh", ["-c", "printf 'one\\ntwo\\n'"], [], 200) |> Stream.map(fn line -> Process.sleep(350); line end) |> Enum.to_list()`
returned only `["one"]`, silently dropping `"two"`. That could lose a
`turn.completed` JSONL event. The worker was asked to drain queued frames in
order and publish wrapper 0.5.7 before completing #182.

The first follow-up patch correctly drained output, but parent review found
that an early downstream halt while the new `:draining` state was active
would still wait five seconds in `close_port/1` even though the port had
already exited. The worker was asked to close `:draining` promptly and cover
three queued lines with `Enum.take(2)` after a slow first-consumer callback.
A separate read-only reviewer was assigned to inspect the final follow-up.
That reviewer found a remaining P2 in the first cleanup change: returning
immediately from `close_port/1` in `:draining` left unread queued Port data in
the caller's mailbox after an early halt. The worker was asked to flush those
matching messages without waiting and add a mailbox regression. The parent
independently reran the two-line reproduction against the updated patch and
observed `["one", "two"]`.

The worker added a nonblocking, port-specific mailbox drain in
`close_port(:draining)` and an isolated-task test that checks both cleanup
latency and absence of leftover Port data. Focused Port tests passed (23),
and the fresh reviewer found no remaining blocking issue on re-review.

The reviewed patch is
[codex_wrapper_ex PR #111](https://github.com/genagent/codex_wrapper_ex/pull/111),
head `34c00b6`. Final local checks: 418 tests passed with four live tests
excluded, formatting, warnings-as-errors compile, Credo, and Dialyzer.
Three CI jobs were pending when this log was updated. Manual merge was
required after CI; no auto-merge was armed. All three jobs passed and #111
merged as `8b6b351e41a6baa98553fbc30e4d7ce3ba612a23`.

Release Please [#112](https://github.com/genagent/codex_wrapper_ex/pull/112)
contained the 0.5.7 version, manifest, changelog, and README changes for
#111, and merged as `3af7d7810667d50b4a5cd440bdae631fcc949cff` after
diff inspection. It reported no PR checks; release workflow `37126562736`
completed successfully. GitHub
[v0.5.7](https://github.com/genagent/codex_wrapper_ex/releases/tag/v0.5.7)
and `mix hex.info codex_wrapper 0.5.7` independently confirmed publication.

After wrapper 0.5.7 published, the worker prepared an isolated adapter
follow-up at `/private/tmp/gen_agent_fix_182b` on
`fix/codex-wrapper-floor-182`. Its diff raises only the Codex integration's
wrapper dependency floor and lock to 0.5.7 and adds an executable regression
that pauses consumption beyond the turn deadline, then confirms the buffered
terminal event still reaches GenAgent. Published-package tests passed (101,
three live tests excluded); formatting, warnings-as-errors compile, and Credo
passed. The parent reviewed this final diff read-only and found no blocking
issue. Dialyzer, docs, PR, and CI were pending at this log update.

The follow-up was committed as `f475fb4` and opened as
[#384](https://github.com/genagent/gen_agent/pull/384). Final published
0.5.7 checks: 101 tests passed with three live tests excluded, formatting,
warnings-as-errors compile, strict Credo, Dialyzer with zero errors, docs,
and diff check. It uses “Part of #182” so the issue remains open through the
adapter release. All 19 PR CI checks passed; the worker manually merged #384
as `172b24c20aff847f5aaaabb4db085d3bc8c12741` at
2026-10-03 13:46:37 UTC. Issue #182 remained open with its in-progress
claim while Release Please Codex PR #380 refreshed to include the follow-up.

Release Please [#380](https://github.com/genagent/gen_agent/pull/380)
refreshed at head `e0b0651` with Codex 0.4.6 manifest/version/changelog
changes. Its changelog includes #384, #383, and prior #377; current main's
Codex dependency floor is `~> 0.5.7`. The bot release branch reported no
checks, so the worker and parent inspected the diff explicitly and relied on
the 19 green fix-PR checks before release merge. #380 merged as
`5fa9511f74fd97f75b79ada6551d44cbd43b9c1a`; release workflow
`37127453700` succeeded. GitHub
[gen_agent_codex-v0.4.6](https://github.com/genagent/gen_agent/releases/tag/gen_agent_codex-v0.4.6)
and `mix hex.info gen_agent_codex 0.4.6` confirmed publication with
`codex_wrapper ~> 0.5.7`. The post-release main CI run `37127453660`
completed successfully, including Codex, minimum-Hex-core, Elixir
1.20/OTP 29, and Hex archives. Issue #182 closed and its in-progress claim
was removed after publication and CI verification.

The preceding main CI run `37127332254` failed only in the Elixir 1.20/OTP
29 lane: the new #98 Registry-loss test started a replacement agent before
the killed Registry partition had finished restarting. The #384 PR CI had
passed, and the post-release OTP 29 lane passed on retry. The parent kept
this distinct from the Codex timeout fix and prepared an isolated #98 test
follow-up at `/private/tmp/gen_agent_fix_98_ci` to wait for the new partition
before asserting that a name can be reused. Its focused test passed 25
consecutive seeds and the full core suite passed 337 tests. Independent
read-only review found no issue. Commit `b716894` was pushed in
`fix/registry-loss-ci-98`, and
[#385](https://github.com/genagent/gen_agent/pull/385) was opened. Its CI
was pending at this log update.

The #113 worker found OpenAI's current main already maps incomplete/refusal
to errors, while Anthropic did not. Its pre-PR evidence: Anthropic 44 tests
(two live excluded), warnings-as-errors compile, Credo, docs, format, and
Dialyzer. It added typed terminal errors, stop details, and unchanged
conversation history for rejected turns in
`/private/tmp/gen_agent_fix_113`. Branch:
`fix/anthropic-terminal-stops-113`; commit: `cb162cb`; PR:
[#381](https://github.com/genagent/gen_agent/pull/381), merged as
`b26cec69ec774374421acd37aeb7329889858600`. All 19 PR checks passed;
issue #113 closed and its claim was removed. Post-merge main CI run
`37125140839` completed successfully. The Anthropic release PR #322
remained separate until the fix was verified.

As a follow-up required to ship #113, the worker inspected the release
contents and squash-merged Anthropic Release Please
[#322](https://github.com/genagent/gen_agent/pull/322) as
`1830e2e9c15e07fdf1dc36381190c9f61a06c474`. It contains version
0.4.0, its changelog with #381/#378, and prior examples. Release workflow
`37125457167` completed successfully. GitHub
[gen_agent_anthropic-v0.4.0](https://github.com/genagent/gen_agent/releases/tag/gen_agent_anthropic-v0.4.0)
and `mix hex.info gen_agent_anthropic 0.4.0` independently confirmed the
release. Post-release main CI run `37125457189` also completed successfully.

The parent still enforced issue selection, ownership, worktree isolation,
independent review, external mechanical checks, CI, merge and release order.
The initial #98 regression taught that a behavior-specific guard must preserve
unregistered low-level server use. The #182 dependency chain shows where a
future high-level control API could coordinate cross-repo repair and release
gates; the work remains tracked by
[server #40](https://github.com/genagent/gen_agent_server/issues/40).

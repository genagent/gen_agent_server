# Three-issue worker batch, 2026-10-03

Josh resumed the 30-minute GenAgent upkeep run and asked for three independent
issues per interval: two delegated to subagents and one handled by the parent.
The switch back to GenAgent Server as the issue worker is gated on a combined
open backlog of 30 issues or fewer. At selection time the four scoped repos
had 105 open issues: 99 in `gen_agent`, 6 in `gen_agent_server`, and none in
the Claude or Codex wrapper repos. This batch therefore used Codex app
subagents. No GenAgent Server provider route was started for implementation.

The selection check inspected open PRs, assignees, and `status/in-progress`
labels. Issues #100, #185, and #255 had no assignee, linked closing PR, or
open overlapping PR. They touch the core client API, Codex CLI adapter, and
HTTP adapters respectively. Each was claimed before editing. The parent and
workers used separate worktrees; the existing dirty main checkout was left
untouched.

## Exact worker instructions

The Codex adapter worker received:

> Own genagent/gen_agent issue #185 only: validate :sandbox and working directory in the Codex adapter's start_session/1, returning {:error, {:invalid_option, key, value}} for bad values before a prompt runs. The issue is already labeled status/in-progress. Check current main and no overlapping PR; old main checkout has unrelated changes, so create a clean isolated checkout/worktree under /private/tmp/gen_agent_fix_185 with branch fix/codex-start-options-185. Do not edit existing in-progress worktrees. Implement minimal fix with meaningful regression tests, run format/compile/tests appropriate to integrations/codex, self-review the diff, record exact checks. Push, open PR, wait for CI, merge if green and safe under user's standing authorization, then clear label and report PR/merge evidence. Preserve checkout if anything is blocked; report rather than silently broadening scope. User has authorized real provider calls but prefer deterministic tests. Do not work #100 or #255. Send progress only for material findings; final with exact result.

The HTTP adapter worker received:

> Own genagent/gen_agent issue #255 only: prevent Anthropic HTTP backend credentials/conversation body leaking through cross-host redirects (and assess OpenAI HTTP backend behavior as relevant). Issue already labeled status/in-progress. Check current main and no overlapping PR. The existing main checkout has unrelated edits; create clean isolated /private/tmp/gen_agent_fix_255 worktree on branch fix/http-redirects-255. Do not touch other in-progress checkouts. Implement a minimal secure fix with meaningful deterministic regression tests (e.g. configure response/redirect handling without real provider calls), run package-appropriate format/compile/test checks, self-review impact. Push PR, wait for CI, merge if green and safe under user's standing authorization, clear label, and report PR/merge evidence. If uncertain about compatibility or CI, preserve work and report. Do not work #100 or #185.

After #255 finished, its worker was reused for a read-only review of #100:

> Please conduct a fresh read-only review of draft genagent/gen_agent PR #379 for core #100. Inspect exact current diff and relevant API/OTP behavior; focus on whether missing-name :noproc matching is safe, PID-name semantics, typedocs/specs, docs accuracy, tests, and any breaking side effects. Do not edit files or post a public review. Return concise findings with severity and exact file/line, or explicit no findings. You just finished #255, so no overlap with your own implementation.

The reviewer found that OTP can return the same wrapped `:noproc` exit when a
registered process *receives* a call and then exits with reason `:noproc`.
The parent changed the core implementation to pre-check registration and to
leave subsequent call exits untouched. A new test reproduces the in-flight
case. Ensemble was updated to map the new `{:error, :not_found}` admission
result to its existing `{:agent_not_running, name}` rejection shape. The
reviewer then received this exact follow-up:

> Thanks for catching the in-flight noproc masking. I revised draft PR #379 at head 90d906d: pre-check registration, then call via name without catch; added a registered process that receives :status then exits :noproc; added narrow Ensemble mapping for {:error,:not_found} to existing {:agent_not_running,name}. Local core 334 and Ensemble 193 tests pass. Please re-review read-only for your original finding and the compatibility mapping; no edits/public review. Report remaining concrete findings or clear.

The re-review found no remaining concrete issue.

## Results and control evidence

| Issue | Branch / isolated checkout | Result | Mechanical evidence |
| --- | --- | --- | --- |
| [#185](https://github.com/genagent/gen_agent/issues/185) | `fix/codex-start-options-185`, `/private/tmp/gen_agent_fix_185` | [PR #377](https://github.com/genagent/gen_agent/pull/377) merged as `255ce7032ec6757f7f4fa5b56c27184c5e8a0465`; issue closed and claim removed | 24 focused tests, 98 Codex tests with three live tests excluded, formatting, warnings-as-errors compile, diff check, all PR CI checks |
| [#255](https://github.com/genagent/gen_agent/issues/255) | `fix/http-redirects-255`, `/private/tmp/gen_agent_fix_255` | [PR #378](https://github.com/genagent/gen_agent/pull/378) merged as `49f719cd2ed15367cc7a94a9a7d7b28169e2e57f`; issue closed and claim removed | Anthropic 42 and OpenAI 54 tests, formatting, all 19 PR CI checks; redirects 302/307/308 exercised in memory |
| [#100](https://github.com/genagent/gen_agent/issues/100) | `fix/api-target-errors-100`, `/private/tmp/gen_agent_fix_100` | [PR #379](https://github.com/genagent/gen_agent/pull/379) merged as `c78c718385f23eddce8d23c3fa903160af074ca9`; issue closed and claim removed | Core 334 tests, Ensemble 193 tests, docs, strict Credo, formatting, all final PR CI checks; independent review and re-review |

The first #100 CI run exposed two separate problems. An OTP 27 lane failed
in an existing supervisor-test cleanup callback unrelated to the client API.
The Ensemble lane failed because the new missing-name tuple changed its
dispatch rejection shape; that was a real regression and was fixed in the
same PR. The updated CI run passed the core, Ensemble, and Hex packaging
lanes. No uncertain provider turn was retried. No real Claude/Codex provider
call was needed.

## Reusable pattern

The host still had to count and claim issues, create isolated Git worktrees,
run mechanical checks, inspect CI, gate review, and publish PRs. This is the
workflow-control gap tracked by [server #40](https://github.com/genagent/gen_agent_server/issues/40).
The issue-worker prompt separated scope, workspace ownership, acceptance
checks, and publication authority; these instructions may become a skill.
The host enforced concurrency, independence, verification, and cleanup.
Review was distinct from test success: its in-flight OTP finding changed the
implementation before the PR could be marked ready.

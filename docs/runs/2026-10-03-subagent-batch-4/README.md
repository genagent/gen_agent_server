# Backend-options fix interval, 2026-10-03

Josh authorized a 30-minute cadence with up to three independent bug fixes,
two delegated and one handled in the calling chat. At selection the four
scoped repositories had 96 open issues: 90 core, six server, and none in
the wrappers. That exceeds the 30-issue switch point, so no GenAgent Server
issue-worker spec, provider call, or server control code was used. The Codex
app design and review subagents inherited the parent's model and effort;
neither was overridden. The parent handled
[core #188](https://github.com/genagent/gen_agent/issues/188) in isolated
worktree `/private/tmp/gen_agent_fix_188` on `fix/backend-options-188`.
The issue was claimed with `status/in-progress` before work. No second or
third issue was safe to claim: the remaining core lifecycle fixes overlap
the active retry [PR #331](https://github.com/genagent/gen_agent/pull/331),
while the Claude translator fix overlaps a separately claimed issue #118.
All unrelated checkouts were preserved.

## Exact delegated instructions

The read-only design worker received:

> Read-only design stage for genagent/gen_agent#188 (claimed by parent). Inspect current consolidated main option handling in integrations/claude, anthropic, openai, codex plus wrapper interfaces. Do not edit or create PR. Propose the smallest compatible fix for unknown-option rejection and aligning names for system prompt, model, timeouts, working directory; identify old names, aliases, deprecation warning strategy, Codex unsupported concepts, where validation must occur, concrete tests, and any semver/breaking risk. Avoid touching in-progress Claude event translator #118 and core retry PR #331. Report source file/line evidence and a staged implementation recommendation to parent. Distinguish bug fixes from optional features; no external provider calls required.

The read-only implementation reviewer received:

> Independent review stage for genagent/gen_agent#188. Inspect uncommitted diff in isolated /private/tmp/gen_agent_fix_188 only; do not edit. Check correctness, compatibility, aliases, validation, tests, and issue acceptance. Four integration suites currently pass. Return prioritized actionable findings with source locations, or say no findings. Pay special attention to deprecation strategy and whether changed Codex unknown errors preserve explicit unsupported options.

The review follow-up received:

> I applied your output-cap distinction and :cwd deprecation warnings; four tests/Credo/docs pass. Please do a quick final read-only re-review of current diff, focusing on any remaining real bug. Timeout semantics are intentionally distinct: HTTP receive, Codex whole runner, Claude stream does not apply config timeout; I plan to document this limitation rather than claim a false alias.

## Findings and mechanical evidence

The issue's earlier claim that Claude silently ignores unknown keys was stale:
current Claude rejects them. The HTTP adapters still ignored typos, and Codex
used `:unsupported_option` for both unsupported concepts and typos. The
shared names are now `:system_prompt`, `:model`, `:max_output_tokens`, and
`:working_dir` where meaningful. Old HTTP prompt/output names and CLI `:cwd`
emit deprecation warnings; conflicting prompt aliases fail startup. Unknown
HTTP keys fail before credential lookup. Codex keeps explicit unsupported
errors for system-prompt and output-cap concepts and gives `:unknown_option`
for misspellings. Timeout names remain backend-specific because the HTTP
receive, Codex runner, and Claude stream settings have different semantics;
the PR description discloses this limit rather than claiming false parity.

The first review found output-cap misclassification and missing `:cwd`
warnings. The parent corrected both. The follow-up review found stale
quick-start examples that would emit warnings; those were changed to the
canonical names. The reviewer found no remaining correctness regression.
Local Anthropic tests: 47 passed, two live excluded; OpenAI: 57 passed, two
excluded; Claude: 91 passed, three excluded; Codex: 103 passed, three excluded.
All four packages passed strict Credo and docs builds. `git diff --check`
passed. The Claude suite logged its expected conflicting-checkpoint task
failure inside a passing regression test. The parent fetched each package's
locked dependencies with `mix deps.get`, ran `mix format`, and ran the full
non-live suites. No external provider calls were needed.

Commit `c99661d` was pushed to `fix/backend-options-188` and
[core PR #389](https://github.com/genagent/gen_agent/pull/389) opened.
The first PR CI attempt passed docs, examples, the Elixir 1.20 core lane,
both minimum Hex-core checks, and all modified adapter lanes. The Elixir
1.19 core lane failed in an unchanged test's `on_exit` callback: it
attempted `GenServer.stop/3` after its task supervisor process was already
gone. The parent reran only the failed job; it passed on attempt 2, and
the dependent Hex archives job then passed. All required CI checks were
green. [Core PR #389](https://github.com/genagent/gen_agent/pull/389)
merged as `68abf7cde4ca185980ac3f8375d94390f98bf3d4` at
2026-10-03T16:42:51Z. Issue #188 closed and its `status/in-progress`
claim was removed. The reusable
control pattern is to verify whether an issue's old finding remains true,
separate truly shared options from similar names with different behavior,
and preserve explicit unsupported errors while normalizing typo errors.
This is input to optional server workflow-control
[issue #40](https://github.com/genagent/gen_agent_server/issues/40).

## Package publication and server consumption

The parent inspected each generated Release Please PR's three-file release
diff. It merged Anthropic [#390](https://github.com/genagent/gen_agent/pull/390),
Claude [#391](https://github.com/genagent/gen_agent/pull/391), Codex
[#392](https://github.com/genagent/gen_agent/pull/392), and OpenAI
[#321](https://github.com/genagent/gen_agent/pull/321). The latter two
release branches conflicted in the shared version manifest after the first
two merges; the parent rebased them in isolated worktrees and retained each
prior package version while updating only the intended component. All four
release workflows succeeded. GitHub releases and `mix hex.info` confirmed
`gen_agent_anthropic` 0.4.1, `gen_agent_claude` 0.2.5,
`gen_agent_codex` 0.4.8, and `gen_agent_openai` 0.4.0 on Hex.

The server's existing locked dependencies were Claude adapter 0.2.3 and
Codex adapter 0.4.5. This branch raises their dependency floors to 0.2.5
and 0.4.8 and locks those versions plus Codex Wrapper 0.5.8. The server
keeps accepting `:cwd` in its own public provider API, but now passes the
canonical `:working_dir` to both CLI adapters. The independent server review
found that `config/runtime.exs` bypassed Providers for the default instance
and still passed `:cwd`; the parent changed those two direct entries too.
With `GEN_AGENT_SERVER_PROVIDERS=claude,codex`, a `mix run --no-start` assertion
verified both default CLI entries contain `:working_dir` and omit `:cwd`.
The full `mix test` suite passed 95 tests after that correction. Normal
server startup now emits no directory-alias warning. No provider call was
needed for the server consumption check.

The server follow-up merged through
[#95](https://github.com/genagent/gen_agent_server/pull/95) as
`5d35187f00afd3fc36e1113e3c47ea5ff92dd57c` after its CI passed 95
tests, warnings-as-errors compilation, formatting, examples, production OTP
release construction, and a packaged MCP smoke test. Version-only
[#96](https://github.com/genagent/gen_agent_server/pull/96) passed the same
CI and merged as `8375a4b65f497b7360c6ae61001b7bb7fc33eac0`.
[GenAgent Server 0.4.1](https://github.com/genagent/gen_agent_server/releases/tag/v0.4.1)
was published from that exact commit and verified public. The parent did not
change or remove any unrelated local checkout. The isolated worktrees were
kept through publication for audit and can be removed after the final log PR.

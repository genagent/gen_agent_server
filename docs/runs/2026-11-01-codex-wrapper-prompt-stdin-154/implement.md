I’ll resume in the existing worktree, compare the edits with issue #154 and the draft PR plan, then finish the implementation and required checks before pushing and marking it ready for review.

The existing branch and draft PR are intact. The edits cover prompt transport, runner setup, argument limits, tests, and docs. I’m using the cj skill to check the prior-session context and will split the review across runner behavior and acceptance coverage.

The implementation sends a literal `-` through stdin in both modes, which the issue permits, and documents that choice. One acceptance detail needs qualification: Forcola’s existing streaming API uses TERM then KILL, while its one-shot API supports INT, TERM, then KILL. I’m checking signal delivery and will report that distinction explicitly.

The first Linux checks pass dependency installation, audit, compilation, and formatting on both runtime versions. Credo found style issues in the new runner code, which are being fixed. The argument-limit tests pass on macOS. I’m also using the Hex skill to verify dependency advisories and the locked Forcola API.

The review found a stream-cleanup bug: an initializer that raised could run a second time during cleanup. That is being fixed with a regression test. The broader tests also caught a Unicode bug in the fake CLI and a changed missing-executable error in Forcola. Native CLI contract checks pass for 0.149.0, 0.164.0, and latest 0.166.0.

The new acceptance tests pass on macOS: 2 MiB prompts arrive intact, `ps -ww` shows no prompt text, timeout signals reach the child, and early stream halt stops it. File tests also pass for 0600/0700 permissions, cleanup, and lazy initialization. The remaining fix preserves Forcola’s typed missing-executable error before the final validation run.

The runner fixes and focused regressions pass. I’ve started the final checks on macOS and both Linux CI runtimes, including docs and all three CLI versions. If those pass, I’ll commit and push the existing branch, then watch the PR’s GitHub checks.

The final review caught one path-resolution edge case: executable lookup must preserve `..` when a path crosses a symlink. That regression now passes. I’m rerunning the complete checks against this last change so the validation matches the code I push.

The full macOS test suite passed. Its contract check hit a local setup issue: CLI 0.149.0 rejects a field in your current Codex config before reaching the probe. I’ll run those checks with a temporary config directory, matching clean CI. Your personal config will stay unchanged.

Both Linux reruns have passed compilation, formatting, Credo, and Dialyzer; the full tests are still running. I’ll record the Forcola streaming SIGINT gap as the one incomplete acceptance detail. The tests verify its existing TERM/KILL schedule and the full INT/TERM/KILL schedule on the other paths.

An existing owner-death test failed on macOS and Linux. Process sampling confirmed that cleanup works: the background child ignores INT and exits on TERM at about two seconds, exactly when the test’s deadline expires. I’m extending that assertion to cover the documented escalation schedule and reaping, then rerunning the checks.

Both Linux runtime matrices now pass, including the full tests and docs, and the source matches the validated snapshot. The macOS run is finishing. I’ve prepared the PR summary with the acceptance results and the Forcola streaming limitation stated explicitly.

All required local checks pass on macOS and both Linux runtimes, including CLI contracts for 0.149.0, 0.164.0, and 0.166.0. I’ve committed the implementation as `63ea405` and will now push it and watch PR #169’s CI.

The push is confirmed at `63ea405`, and the worktree is clean. GitHub’s Docs job has passed; the two runtime jobs and pinned CLI contract jobs are still running. The PR remains draft until they finish.

Docs and both pinned CLI contract jobs are green. The two runtime jobs are still running Dialyzer, with their tests to follow. No CI failures have appeared.

Both runtime jobs have passed Dialyzer and are running their final test step. Docs and both CLI contract jobs are green. Once the tests pass, I’ll update the PR body and mark it ready.

All five GitHub CI jobs passed on `63ea405`. I’m replacing the plan with the final changes, validation results, and acceptance status, then marking PR #169 ready for review. I won’t merge it.

[PR #169](https://github.com/genagent/codex_wrapper_ex/pull/169) is **ready for review**, with its body updated. Not merged. Worktree is clean.

Commits:

- `f200c7c`: `feat: start prompt on stdin (#154)`
- `63ea405`: `feat: deliver prompts on stdin (#154)`

All required local checks passed on macOS and both Linux CI runtimes: `mix deps.get`, `mix deps.unlock --check-unused`, `mix hex.audit`, `mix compile --warnings-as-errors`, `mix format --check-formatted`, `mix credo --strict`, `mix dialyzer`, `mix test`, and `mix docs --warnings-as-errors`.

Each suite reported **692 tests, zero failures, four authenticated integration exclusions**. `mix codex.contract` passed for CLI **0.149.0, 0.164.0, and 0.166.0**. [Final GitHub CI](https://github.com/genagent/codex_wrapper_ex/actions/runs/41276007134): **all five jobs passed**.

Acceptance results:

1. **Done:** stdin transport across all four commands, both runners, execute/stream, and sessions.
2. **Done:** 0600/0700 permissions, unlink before execution, and failure/timeout/halt cleanup.
3. **Not fully done:** 2 MiB integrity, process-table privacy, and signal tests pass. Forcola streaming retains TERM/KILL only because Forcola 0.7.0 lacks streaming INT support. Explicitly documented in the PR.
4. **Done:** oversized argv/environment inputs produce typed errors before target launch.
5. **Done:** argv compatibility, literal `-` handling, and updated documentation.

Remaining limitations: forced owner/VM death before unlink can leave a private prompt file; executable preflight cannot eliminate filesystem races.

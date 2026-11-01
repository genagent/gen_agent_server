I’ll fix defects 1–7 in the existing worktree, add focused regressions and the Port error changelog note, then rerun every local check and wait for CI. I’ll also update the PR’s breaking-change metadata and remove the `codex154-*` Docker resources when validation is complete.

The review’s failure paths match the code. I’m addressing argument-limit discovery, file allocation, and launcher errors in parallel, with regressions for each. I’ll leave the owner-death test change in its existing published commit; separating it would require rewriting the branch history.

The focused regressions now pass for PATH-based `getconf` discovery, cached limits, a 40 KiB inherited environment, bounded directory-collision retries, launcher exit 125, evidenced spawn errors, and a deleted VM working directory. I’ve also added the changelog note for Port startup errors. I’m moving on to the full checks.

The final code review found no remaining defects in the fixes. Both Linux runs have passed dependencies, audit, compilation, formatting, Credo, and Dialyzer; their full test suites are running. I’ll keep the Docker environments available until GitHub CI passes in case a fix needs another local run.

The Linux checks pass, but the full macOS suite caught a regression in the suggested `command exec` change: Port children start, then execution waits until timeout after they exit. I’m investigating that shell-specific behavior and will preserve both the startup-error status and watchdog cleanup before pushing.

The macOS failure is traced to Bash 3.2 hanging after `command exec`. The launchers now use plain `exec` with a temporary EXIT trap to return 125 on an open failure. All 52 transport and lifecycle checks pass on macOS. The stalled test launchers have been removed, and I’m restarting the full validation.

The fresh runs have passed compilation, formatting, Credo, and Dialyzer on all three environments. The full tests are progressing without the macOS hangs. After they pass, I’ll push the review fixes, wait for CI, apply the exact `feat!:` title and opening `BREAKING CHANGE:` paragraph, then remove the Docker resources.

All required local checks pass on macOS and both Linux runtimes: 705 tests reported, zero failures, four integration exclusions, plus all three CLI contracts. The fixes are committed as `bdb454f`, `1191afb`, and `668d032`. I’m pushing them and watching GitHub CI.

The review-fix push is confirmed. GitHub’s Docs job and both pinned CLI contracts are green; both runtime jobs are in Dialyzer. The PR remains ready for review. I’ll update its title and body and remove the Docker resources once the run is fully green.

Both runtime jobs have passed Dialyzer and reached their test step. The other three jobs are green. The worktree is clean, and the code matches the locally validated snapshot.

All five GitHub CI jobs passed. I’m applying the exact `feat!:` title and opening `BREAKING CHANGE:` paragraph now, then deleting the four task containers and two `codex154-local*` images.

[PR #169](https://github.com/genagent/codex_wrapper_ex/pull/169) remains **ready for review**, retitled `feat!: deliver prompts on stdin`. Not merged. Worktree is clean.

Fixed defects:

1. Discover `getconf` through PATH, with `/usr/bin/getconf` fallback and Linux 2 MiB / Darwin 1 MiB defaults.
2. Cache limits in `:persistent_term`.
3. Use 128-bit random directory names and five bounded creation attempts.
4. Return exit 125 through portable EXIT traps. Added regressions covering the macOS Bash 3.2 `command exec` hang.
5. Preserve `{:spawn, reason}` termination evidence for executable failures.
6. Return typed spawn errors when the VM’s cwd is deleted.
7. Added the required opening `BREAKING CHANGE:` paragraph naming argv changes and custom-runner stdin requirements.

Also added the Port startup-error changelog note. The owner-death test change remains in its original published commit, avoiding history rewriting.

New commits:

- `bdb454f`: `fix: cache portable argument limits`
- `1191afb`: `fix: harden stdin setup and spawn errors`
- `668d032`: `docs: record stdin transport breaking changes`

All required checks passed on macOS and both Linux runtime combinations: dependencies, unused dependencies, Hex audit, strict compilation, formatting, Credo, Dialyzer, tests, and strict docs. Each suite reported **705 tests, zero failures, four integration exclusions**. CLI contracts passed for **0.149.0, 0.164.0, and 0.166.0**.

[Final GitHub CI](https://github.com/genagent/codex_wrapper_ex/actions/runs/41277549492): **all five jobs passed**.

Removed Docker resources:

- Containers: `codex154-init119`, `codex154-init120`, `codex154-119`, `codex154-120`
- Images: `codex154-local119:latest`, `codex154-local120:latest`

Verified no `codex154-*` containers or images remain.

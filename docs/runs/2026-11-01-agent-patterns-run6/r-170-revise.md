Fixes are committed locally. [PR #170](https://github.com/genagent/codex_wrapper_ex/pull/170) was already merged, so delivery remains unresolved.

New commit: `a4cf14f0fa5a` `fix(env)!: preserve release environment policy in IEx sessions`

| Acceptance item | Status |
|---|---|
| Route `release_env` through IEx chat/resume | Done |
| Test policy persistence through later `say/2` calls | Done, both policies |
| Document custom-runner `false` removals and changelog requirement | Done |
| Breaking PR title and commit footer | Done |
| Issue #156: spawn coverage, overrides, opt-out, fabricated/fake-CLI tests, README/changelog | Done, existing coverage passed |
| Push, updated PR body, new CI, ready transition | Not done: PR already merged |

All local checks passed:

- Elixir **1.19.7/OTP 27.3.4.19** and **1.20.5/OTP 29.1.2**: dependencies, unused-dependency check, Hex audit, warnings-as-errors compilation, formatting, strict Credo, Dialyzer, and full tests. Each suite reported **740 tests, zero failures**, with four integration exclusions.
- Docs with warnings as errors.
- Node **22.23.4** CLI contracts: **0.149.0**, **0.164.0**, latest **0.166.0**.
- Native focused IEx suite: **13 tests, zero failures**.
- `git diff --check`.

`gh pr checks --watch` confirmed the merged PR’s original five jobs are green. Those checks do **not** cover the new local commit. All task-created check artifacts and containers were removed; the worktree is clean.

Delivery needs your choice: keep the commit local, push the existing branch, or authorize a follow-up PR. A new PR requires authorization because your instructions prohibit one. Changing #170’s title does not change its existing squash commit or release-please history.

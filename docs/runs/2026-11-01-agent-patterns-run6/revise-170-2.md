Deliver your commit a4cf14f as a follow-up pull request. #170 was squash-merged to main as `feat(env)!: scrub release variables from child processes`, so the breaking change is already declared.
- `git fetch`, then create a new branch `fix/156-iex-release-env` from origin/main in a new worktree next to this one, and cherry-pick a4cf14f onto it.
- Reword the commit to `fix(env): route release_env through IEx chat and resume`, with no `!` and no `BREAKING CHANGE` footer (a second one would list the break twice in the release notes). Keep the body describing the IEx fix, the runner typedoc and the CHANGELOG sentence.
- Open it as a draft PR first referencing #156 and #170, run every CI check locally, push, wait for CI, then update the body to what changed and what was checked and mark it ready. Do not merge.
- Remove the old worktree ../codex_wrapper_ex-156 and its local branch feat/156-release-child-env when the new PR is ready; it is merged.
Same rules as before for identity, trailers, prose and cleanup. Report the PR URL, the commit, checks, CI status.

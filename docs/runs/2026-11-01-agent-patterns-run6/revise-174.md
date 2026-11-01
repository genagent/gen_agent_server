You are in the worktree for open pull request genagent/codex_wrapper_ex#174 (branch fix/156-iex-release-env), a follow-up to #170 (issue #156). #170's squash commit on main (590ef0b) is `feat(env): scrub release variables from child processes (#170)` with no `!` and no footer; only its PR title was changed afterwards. So the breaking change is not declared on main, and #174 must declare it.

Do not rewrite history. Instead:
- Change the PR title to `fix(env)!: route release_env through IEx chat and resume`.
- Add one empty commit (`git commit --allow-empty`) with subject `fix(env)!: declare the release environment scrub from #170 as breaking` and a `BREAKING CHANGE:` footer describing the default scrub of RELEASE_*, BINDIR, ROOTDIR and release PATH entries inside a release, the `release_env: :inherit` opt-out, and that custom runners must honour `{name, false}` env entries. Push normally.
- Add a sentence to the PR body saying the squash commit must keep the `!` title and the BREAKING CHANGE footer.
The tree is unchanged, so skip the local check suite. Wait for CI, keep the PR ready, and report the new commit hash and CI status. Commit only as the configured identity, no trailers, no AI attribution, no em dashes.

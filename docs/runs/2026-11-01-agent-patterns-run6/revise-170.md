Revise open pull request genagent/codex_wrapper_ex#170 (issue #156, release environment scrub for the codex child). You are in its worktree, on branch feat/156-release-child-env; a previous agent wrote the change and has finished. Read the issue and the PR (`gh issue view 156`, `gh pr view 170`, `gh pr diff 170`, all with `-R genagent/codex_wrapper_ex`). Do not create a new branch or PR.

Two independent reviews found these. Fix each, with a test where behaviour changes:
1. lib/codex_wrapper/iex.ex:213: `@config_keys` omits `:release_env`, so `CodexWrapper.IEx.chat("hello", release_env: :inherit)` and `resume/2` forward it as an exec option and raise `unknown option :release_env`. Add it, and test both entry points, including that the policy holds for later `say/2` calls.
2. lib/codex_wrapper/runner.ex:81: the runner contract typedoc says `:env` is `{name, value}` string tuples. Inside a release every spawn now passes `{name, false}` unsets, so a custom runner written to that contract breaks by default. Document `{name, String.t() | false}` with `false` removing an inherited variable, and say in the CHANGELOG breaking entry that custom runners must honour `false` entries.
3. The CHANGELOG files this under Breaking Changes, but the commit is `feat(env): ...` without `!`, so release-please will not list it as breaking. Make the PR title `feat(env)!: ...` and give the new commit a `BREAKING CHANGE:` footer describing the default scrub inside a release.
Not required: the double System.get_env read on the Forcola one-shot path (reviewer rated it minor); leave it, or fix it if it is small.
Repository owner's rules, which apply to everything you do:
- Commit only as the git identity already configured. Do not change the author or committer. Do not add Co-Authored-By or any other trailer, and no AI attribution anywhere in commits, PR text or comments.
- Conventional-commit prefixes for commits. Writing in commits, PR text and docs: factual, no marketing tone, no em dashes.
- Before every push, run every check the CI workflow runs: read .github/workflows/*.yml and run each job's commands locally, including any matrix of CLI or runtime versions you can reproduce. Push only when they pass.
- Remove anything you start for checks (containers, temporary directories, background processes) before you finish.
- After the final push, wait for the PR's CI (`gh pr checks --watch`). If a job fails, read its log, fix it, and push again. When CI is green, update the PR body from plan to what changed and what was checked, then mark it ready with `gh pr ready`. Do not merge.


Finish with a report: the PR URL, each commit (hash and subject), the checks you ran with results, the final CI status, each acceptance item with done or not done, and anything you are unsure about.

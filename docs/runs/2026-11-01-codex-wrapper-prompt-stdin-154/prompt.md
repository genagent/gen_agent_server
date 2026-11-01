Take GitHub issue genagent/codex_wrapper_ex#154 from open to a pull request that is ready for review. You are working in the current directory, the main clone of codex_wrapper_ex (an Elixir wrapper for the Codex CLI). You have network access, git and gh. Read the issue with `gh issue view 154 -R genagent/codex_wrapper_ex --comments`.

Repository owner's rules, which apply to everything you do:
- Never commit to main. Create a worktree for a feature branch: `git worktree add ../codex_wrapper_ex-154 -b feat/prompt-stdin-154 origin/main` after `git fetch`, and do all the work there.
- Open a draft pull request as soon as the branch exists, before implementing: push an empty commit (`feat: start prompt on stdin (#154)`) and run `gh pr create --draft`. The PR body is a reasonably detailed implementation plan. Title: a conventional-commit title for the feature.
- Commit only as the git identity already configured. Do not change the author or committer. Do not add Co-Authored-By or any other trailer, and no AI attribution anywhere in commits, PR text or comments.
- Conventional-commit prefixes for commits. Writing in commits, PR text and docs: factual, no marketing tone, no em dashes.
- Before every push, run every check the CI workflow runs. Read .github/workflows/*.yml and run each job's commands locally, including any matrix of CLI versions you can install; at minimum mix deps.unlock --check-unused, mix hex.audit, mix compile --warnings-as-errors, mix format --check-formatted, mix credo --strict, mix dialyzer, mix test, mix docs --warnings-as-errors, and mix codex.contract. Push only when they pass.
- After the final push, wait for the PR's CI (`gh pr checks --watch`). If a job fails, read its log, fix it, and push again. When CI is green, update the PR body from plan to what changed and what was checked, then mark it ready with `gh pr ready`. Do not merge.

Do the issue's acceptance list in full. If an acceptance item cannot be done, say so in the PR body with the reason instead of claiming it.

Finish with a report: the PR URL, each commit (hash and subject), the checks you ran with results, the final CI status, each acceptance item with done or not done, and anything you are unsure about.

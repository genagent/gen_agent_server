Repository owner's rules, which apply to everything you do:
- Never commit to main. After `git fetch`, create a worktree next to this clone for a feature branch named with a conventional prefix and the issue number, and do all the work there.
- Open a draft pull request as soon as the branch exists, before implementing: push an empty start commit and run `gh pr create --draft`. The PR body is a reasonably detailed implementation plan. Title: a conventional-commit title for the change.
- Commit only as the git identity already configured. Do not change the author or committer. Do not add Co-Authored-By or any other trailer, and no AI attribution anywhere in commits, PR text or comments.
- Conventional-commit prefixes for commits. Writing in commits, PR text and docs: factual, no marketing tone, no em dashes.
- Before every push, run every check the CI workflow runs: read .github/workflows/*.yml and run each job's commands locally, including any matrix of CLI or runtime versions you can reproduce. Push only when they pass.
- Remove anything you start for checks (containers, temporary directories, background processes) before you finish.
- After the final push, wait for the PR's CI (`gh pr checks --watch`). If a job fails, read its log, fix it, and push again. When CI is green, update the PR body from plan to what changed and what was checked, then mark it ready with `gh pr ready`. Do not merge.

Do the issue's acceptance list in full. If an acceptance item cannot be done, say so in the PR body with the reason instead of claiming it.

Finish with a report: the PR URL, each commit (hash and subject), the checks you ran with results, the final CI status, each acceptance item with done or not done, and anything you are unsure about.

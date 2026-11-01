# Working one issue through the server

The procedure an operator (a person, or a Claude Code session acting for one)
follows to take one GitHub issue from open to a ready pull request, with the
code change made by an agent running in the server. Each step names what the
operator does by hand today. Steps that repeat the same commands on every run
are candidates for an optional helper; [dogfooding.md](dogfooding.md) records
the runs, and the [friction log](#friction-log) below records what each run
showed about this procedure.

The operator owns git and GitHub: branches, commits, pushes and pull requests
are made by the operator under the repository owner's identity. The agent
edits files and runs commands inside one worktree and does nothing outside it.

## Roles

| Role | Does |
| --- | --- |
| Operator | Picks the issue, prepares the worktree, writes the prompt, verifies the result, commits, pushes, opens and maintains the pull request, records the run |
| Server | Holds one instance per issue, routes the prompt to the agent, keeps the invocation result |
| Agent | Edits and tests inside the worktree; reports what it changed and what it ran |
| Repository owner | Reviews and merges |

## Steps

### 1. Server preflight

Build and start the release once per session, from a clean server checkout.

```bash
cd gen_agent_server
MIX_ENV=prod mix release --overwrite
export RELEASE_NODE=gen_agent_server
_build/prod/rel/gen_agent_server/bin/gen_agent_server daemon
mix gen_agent_server.remote instances
```

Record the server commit and the provider CLI versions (`codex --version`,
`claude --version`) in the run record.

### 2. Read the issue

```bash
gh issue view N -R OWNER/REPO --json title,body,comments,labels
```

Confirm the issue is not blocked, its acceptance criteria are checkable, and
any decision recorded in comments is reflected in the plan.

### 3. Prepare the worktree

```bash
git -C REPO fetch origin
git -C REPO worktree add ../REPO-N -b feat/SLUG origin/main
cd ../REPO-N
mix deps.get && mix compile && mix test
```

Fetch dependencies and compile before the agent starts: a Codex
`workspace_write` sandbox has no network, so `mix deps.get` cannot run inside
it. A baseline test run separates existing failures from ones the agent adds.

### 4. Open the draft pull request

Push the branch with an empty commit and open a draft pull request whose body
is the implementation plan, before the agent runs.

```bash
git commit --allow-empty -m "feat: start SLUG (#N)"
git push -u origin feat/SLUG
gh pr create --draft --title "feat: ..." --body-file plan.md
```

### 5. Create the instance

One instance per issue, named for it, with one write-capable route whose cwd
is the worktree.

```bash
MIX_QUIET=1 mix gen_agent_server.ops create_instance --remote \
  --instance REPO-N \
  --config '{"cwd": "/abs/REPO-N", "routes": [{"name": "impl", "provider": "codex", "codex_sandbox": "workspace_write"}]}'
```

### 6. Write the prompt

The prompt carries the issue text and the operating constraints:

- Work only inside the current directory. Do not run git commands that change
  history or remotes (`commit`, `push`, `checkout`, `reset`).
- Follow the repository's conventions (AGENTS.md, CONTRIBUTING.md).
- Run the repository's checks before finishing and report the exact commands
  and results.
- End with a summary: files changed, behaviour added, tests added, anything
  not done and why.

Keep the exact prompt in the run record.

### 7. Invoke and wait

```bash
MIX_QUIET=1 mix gen_agent_server.ops invoke --remote --instance REPO-N --agent impl --prompt "$(cat prompt.txt)"
MIX_QUIET=1 mix gen_agent_server.ops result --remote --instance REPO-N --id ID
```

### 8. Verify outside the agent

The agent's report is evidence about the task, not proof. The operator:

- reads the full diff (`git diff`, `git status` for new files);
- runs the repository's checks on the host;
- checks each acceptance criterion against the code and tests, and marks any
  criterion the change does not meet.

### 9. Revise

For each finding, send a follow-up prompt to the same route so the agent keeps
its session, then repeat step 8. Small fixes the operator can state exactly may
be made by hand instead; the run record says which.

### 10. Commit, push, finish the pull request

Commit as the repository owner with a conventional-commit message, run the
checks again, push, update the pull request body with what changed and what
was checked, wait for CI, and mark the pull request ready.

### 11. Record and clean up

- Add a run record under `docs/runs/DATE-SLUG/README.md` and a row in
  [dogfooding.md](dogfooding.md): task, provider and version, prompt, result,
  revisions, host checks, and each observation classified as mechanical,
  behavioural or mixed.
- Add new friction to the log below.
- `stop_instance` the issue's instance. Remove the worktree after the pull
  request merges.

## Friction log

Each entry names the step, what happened, and the candidate response: a change
to this procedure, a server or core fix, or an optional helper.

| Run | Step | Observation | Candidate response |
| --- | --- | --- | --- |

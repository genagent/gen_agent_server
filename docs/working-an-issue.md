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
export RELEASE_NODE=gen_agent_server_dogfood
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

For a Codex `workspace_write` route, also tell the agent what the sandbox
blocks, so it neither works around it silently nor reports it as a failure of
its change:

- no network: no `mix deps.get`, no live provider calls; native CLI probes
  are run by the operator on the host;
- Mix's TCP concurrency lock: run Mix with `MIX_OS_CONCURRENCY_LOCK=0`;
- process inspection (`ps`): tests that inspect OS processes fail in the
  sandbox; the host test run is authoritative.

Keep the exact prompt in the run record.

### 7. Invoke and wait

```bash
MIX_QUIET=1 mix gen_agent_server.ops invoke --remote --instance REPO-N --agent impl --prompt "$(cat prompt.txt)"
MIX_QUIET=1 mix gen_agent_server.ops result --remote --instance REPO-N --id ID
```

`result` returns `"status": "pending"` until the turn ends; nothing waits for
it, so the operator polls:

```bash
until MIX_QUIET=1 mix gen_agent_server.ops result --remote --instance REPO-N --id ID > result.json &&
  ! grep -q '"status": "pending"' result.json; do sleep 30; done
```

A completed result has `status`, `text`, `usage`, `session_id` and
`duration_ms`. It does not say which model ran or which files changed.

### 8. Verify outside the agent

The agent's report is evidence about the task, not proof. The operator:

- reads the full diff (`git diff`, `git status` for new files);
- runs the repository's checks on the host;
- checks each acceptance criterion against the code and tests, and marks any
  criterion the change does not meet;
- runs any acceptance step the sandbox prevented, such as a native CLI probe,
  and passes the observed result to the agent in step 9.

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
| [codex_wrapper #153](runs/2026-11-01-codex-wrapper-153/README.md) | 1 | `mix.exs` pins gen_agent `~> 0.11.0`, gen_agent_claude `~> 0.4.0`, gen_agent_codex `~> 0.7.0`, so the release does not use core 0.12 or the current adapters. | Server fix: widen the requirements. |
| codex_wrapper #153 | 3 | Two clones of each wrapper exist locally (under `genagent/` and `joshrotenberg/`); the operator has to know which one is current. | Environment; no server change. |
| codex_wrapper #153 | 7 | String parameters do not accept `@path`, so the prompt goes on argv through `"$(cat prompt.txt)"`. | Helper: [#144](https://github.com/genagent/gen_agent_server/issues/144). |
| codex_wrapper #153 | 7 | Nothing waits for a result; the operator polls `result` in a shell loop (7 polls for a 174 s turn). | Server fix: a wait timeout on `result`, or a blocking await operation. |
| codex_wrapper #153 | 7 | Mix's TCP concurrency lock is blocked in the Codex sandbox; the agent found `MIX_OS_CONCURRENCY_LOCK=0` itself. | Procedure: stated in step 6. Candidate server fix: set it in the Codex child env for `workspace_write` routes. |
| codex_wrapper #153 | 7 | `ps` is blocked in the sandbox; 14 existing process-cleanup tests failed in the agent and passed on the host. | Procedure: stated in step 6; the host run is authoritative. |
| codex_wrapper #153 | 7 | No network in the sandbox; the native probe in the acceptance list could not run, and the agent recorded the blocked attempt. | Procedure: native probes are the operator's (steps 6 and 8). |
| codex_wrapper #153 | 7 | The result has no model name and no list of changed files. | Candidate server fix: model in the result. Changed files come from `git status`. |
| codex_wrapper #153 | 9 | The revision turn reused the implementation session and took 19 s. | None; works as intended. |
| [server #135](runs/2026-11-01-server-result-wait-135/README.md) | 3 | gen_agent_server extensions are separate Mix projects; dependencies for seven of them had to be fetched before the sandboxed run. | Procedure: step 3 covers every Mix project in the repository. |
| server #135 | 8 | A Claude read-only review found three defects the operator had missed, and made one false claim (dead code that a test still calls). | Procedure: a review route before host checks; the operator checks claims before forwarding. |
| server #135 | 8 | The read-only Claude route cannot run `git diff`, so the diff went into the prompt. | None at 22 KB. |
| server #135 | 10 | One CI failure was an existing race in a control extension test helper, unrelated to the change. | Rerun; separate fix. |
| [claude_wrapper #328](runs/2026-11-01-claude-wrapper-print-flags-328/README.md) | 6 | A read-only triage turn wrote the PR plan and the implementation prompt; the operator used both unedited. | Procedure: triage before implementation. |
| claude_wrapper #328 | 7 | A Claude `accept_edits` route edits files but cannot run Bash headless; 848 lines arrived without a compile or test run. | Server fix: #137 (inherit by default). |
| claude_wrapper #328 | 8 | Host checks ran the contract against the installed CLI only; CI also pins 2.1.220, which failed. | Helper: run the gates the CI workflow defines. |
| [server #137](runs/2026-11-01-server-inherit-access-137/README.md) | 8 | Host checks skipped the MCP release smoke that CI runs; CI failed on an outdated assertion. | Helper: same as above; second run in a row. |
| server #137 | 11 | An agent drafted the run records for runs 3 and 4 from artifacts and operator notes; the operator added one event the notes predated and two scorecard cells. | Procedure: agent draft, operator check. |
| server #137 | 7 | With inheritance, a Codex route with no access options and a Claude `auto` route both ran a networked command. | Next run hands a whole issue to one inherited session. |
| [codex_wrapper #154](runs/2026-11-01-codex-wrapper-prompt-stdin-154/README.md) | 7 | GenAgent's default 10-minute `watchdog_ms` ended a whole-issue turn; the server does not expose it. | Server fix: turn limit opt-in per route or call, default none. |
| codex_wrapper #154 | 3 to 10 | One inherited session did the worktree, draft PR, implementation, local CI matrix (Linux in Docker, three CLI versions), commits, push, CI and ready, from one prompt with the owner's rules. | Procedure: steps 3, 4 and 8 to 10 move to the session. |
| codex_wrapper #154 | 8 | An independent read-only review found seven defects after the session's self-review. | Procedure: keep an independent review before merge. |
| codex_wrapper #154 | 11 | The session left Docker containers and images until asked to remove them. | Procedure: the prompt asks for cleanup of what the session creates. |
| [run 6 patterns](runs/2026-11-01-agent-patterns-run6/README.md) | 5 | The `agent` call over the wrappers alone (#140) carried three parallel sessions to five ready PRs; nothing in the runs needed GenAgent or Ensemble. | Server: build `agent` on the wrappers; keep GenAgent for HTTP backends. |
| run 6 patterns | 5 | Claude `inherit` resolves to the user's settings, not the creator's mode; headless, it cannot run Bash. | Procedure: pass the creator's mode as `access`. Server: [#143](https://github.com/genagent/gen_agent_server/issues/143). |
| run 6 patterns | 8 | Two reviewers on one PR (Claude and the Codex counterpart) found disjoint defects; an independent Claude review found seven items after the implementer's own Codex reviewer. | Procedure: keep the independent review even when the implementer reviews itself. |
| run 6 patterns | 9 | PRs were merged while their reviews ran; the revisions found them merged. | Procedure: merge after review; the prompt says what to do if the PR is already merged. |
| run 6 patterns | 9 | A session removed its own cwd; the next turn failed as `{:exit, 2, ""}` with empty stderr. | Server fix: [#141](https://github.com/genagent/gen_agent_server/issues/141). |
| run 6 patterns | 7 | Parallel `mix gen_agent_server.ops` calls from one checkout wait on the Mix build lock, and the operator's `MIX_QUIET=1` leaked into every session through the daemon's env. | Packaging: [#145](https://github.com/genagent/gen_agent_server/issues/145). |
| run 6 patterns | 8 | A stopped session leaves no record, so self-started reviewers are known only from the implementer's report. | Server fix: [#142](https://github.com/genagent/gen_agent_server/issues/142). |

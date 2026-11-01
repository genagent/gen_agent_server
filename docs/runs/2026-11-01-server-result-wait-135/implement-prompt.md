You are implementing one GitHub issue in gen_agent_server, an Elixir OTP application. The current directory is a git worktree of the repository on branch feat/result-wait-135. Dependencies are fetched and compiled for the root project and for every project under extensions/.

Constraints:
- Work only inside the current directory.
- Do not run git commands that change history, branches or remotes (commit, push, checkout, reset, rebase, stash). Reading with git status, git diff and git log is fine.
- Follow the conventions of the existing code: module layout, moduledoc and @doc style, typespecs, test style. lib/gen_agent_server/invocations.ex is where waiting belongs; the result operation is in lib/gen_agent_server/ops.ex; the CLI is lib/gen_agent_server/cli.ex; the Mix tasks are under lib/mix/tasks.
- The sandbox has no network, blocks Mix's TCP concurrency lock and blocks process inspection such as ps. Run Mix with MIX_OS_CONCURRENCY_LOCK=0. Do not try to fetch dependencies or call live providers. If a test fails only because of the sandbox, say so; the host test run is authoritative.
- Before finishing, run and fix: mix format, mix compile --warnings-as-errors, mix test in the root, and mix test in extensions/mcp (its tool list is generated from the operations catalogue).
- Finish with a summary: files changed, the public API added, tests added, the exact check commands you ran with their results, and any acceptance item you did not do, with the reason.

The issue follows.

# feat: wait for a terminal result on result

## Problem

`result` reads an invocation once and returns `{:ok, :pending}` while the turn runs. Nothing waits for a terminal result, so a caller that submitted with `invoke` polls `result` in a loop. In the first run of the one-issue procedure (#134, `docs/runs/2026-11-01-codex-wrapper-153`), a 174 s Codex turn took 7 polls of `mix gen_agent_server.ops result --remote` at 30 s intervals, each starting a Mix VM and an RPC.

`ask` waits, but it submits a new prompt; it cannot wait on an invocation that already exists.

Completions reach `GenAgentServer.Invocations` through its timed inbox poll (`schedule_poll/1`, `handle_info(:collect, ...)`) and are recorded in `record_completion/2`, including cancellations, which arrive as `{:error, :cancelled}`.

## Change

- `GenAgentServer.result(instance, id, opts)` accepts `wait_ms:` (integer, 0 to 600_000, default 0). `result/2` keeps today's behaviour.
- With `wait_ms > 0` and a pending invocation, `Invocations` keeps the caller as a waiter for that ID and replies when `record_completion/2` records it (completed, failed or cancelled), or replies `{:ok, :pending}` when `wait_ms` elapses. A poll is scheduled while any waiter exists. Completed, failed and unknown IDs reply at once, as today.
- Invalid `wait_ms` returns `{:error, :invalid_wait}` before any lookup.
- Waiters do not block the instance: other calls (`invoke`, `result`, `cancel`, `invocations`) are served while a caller waits.
- Surfaces:
  - the `result` operation gets an optional `wait_ms` parameter; the MCP extension's tool picks it up from the catalogue;
  - `mix gen_agent_server.ops result --remote` sets its RPC timeout to `wait_ms` plus the usual margin;
  - the CLI accepts `result ID --wait MS`, and `mix gen_agent_server.remote` sets its RPC timeout to match.
- README: document the wait on `result`.

## Acceptance

- [ ] A waiter receives the terminal result when the invocation completes, fails, or is cancelled.
- [ ] A waiter receives `{:ok, :pending}` after `wait_ms` with no completion.
- [ ] Two waiters on one ID both receive the result.
- [ ] While one caller waits, `invoke` and `result` on the same instance return without waiting for it.
- [ ] `wait_ms` of 0 or absent behaves exactly as today; out-of-range or non-integer values return `{:error, :invalid_wait}`.
- [ ] The remote ops task and remote CLI do not time out before `wait_ms` elapses.
- [ ] Format, warnings-as-errors compile, Credo, tests and docs pass, including the extension matrix.


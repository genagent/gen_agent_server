You are reviewing a change to gen_agent_server, an Elixir OTP application, before it is committed. The current directory is the worktree with the change applied. You can read any file. You cannot run commands; the operator runs the tests.

Review the change against the issue below. Report:
1. For each acceptance item: met, not met, or not verifiable by reading, with the file and line that shows it.
2. Defects: incorrect behaviour, races, missing cases, inconsistencies with the surrounding code's conventions. For each, file:line, what is wrong, and a concrete fix.
3. Anything in the diff that the issue did not ask for.
4. A verdict on the last line: APPROVE or REQUEST CHANGES.

Report only what you can point to in the code. Do not restate the change.

# Issue: feat: wait for a terminal result on result

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

# Diff

The diff of the implementation turn followed here; see implement.diff.

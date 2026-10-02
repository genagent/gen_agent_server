**Verdict: confirmed on 03fcc02 (`origin/main` and HEAD are the same commit).** `finish_error/3` (`lib/gen_agent/server.ex:1735`) calls `record_error/3` without condition, before it looks at the transition. So the ask gets `{:error, reason}` right away, or the tell stores it and sends a completion. The retry then goes through `accept_self_chain/2` as a bare prompt, and the `:process_next` clause (`server.ex:324`) dispatches it with a fresh `make_ref()` as `:self_chain`. `record_success/3` throws that result away. `server_test.exs:704-720` locks this behavior in by asserting `{:error, :rate_limited} = ask(...)`.

## Affected functions (all in `server.ex`)
- **Core change:** `finish_error/3`, `accept_self_chain/2`, `enqueue_self_chain/2`, and the self-chain clause of `dispatch_event(:internal, :process_next, ...)`.
- **Visibility:** the `{:poll, ref}` clause, the `{:cancel_request, ref}` clause, `current_tell_ref?/2`, `cancel_queued_tell/3`, `transition_to_halted/1` / `fail_halt_aware_queued/1`, and the `runtime_snapshot` clause.
- **Overflow path:** `reject_generated_prompt/3`, `enqueue_error_recovery_prompt/2`.
- **Telemetry:** `emit_turn_start/stop/error`, `emit_prompt_start/stop/error`.
- **Docs:** `@callback handle_error` docs in `lib/gen_agent.ex`, `lib/gen_agent/telemetry.ex`, CHANGELOG, MIGRATION.

## Contract
**Scope.** When `handle_error/3` returns `{:prompt, p, s}` for a turn owned by `{:ask, from}`, `:tell`, `{:tell, r}` or `{:tell, r, on_halt}`, it becomes a **caller-owned retry**:
- `record_error` is skipped.
- `post_turn` still runs with `{:error, reason}`.
- The self-chain slot holds `{:retry, p, kind, ref, attempt + 1}` instead of a binary.

Two things stay as they are today, as independent follow-ups:
- `handle_response/3` returning `{:prompt}`.
- `handle_error/3` on `:self_chain` or `:event` turns.

**ask.** One reply, carrying the final attempt's outcome: success, or the last error once `handle_error` returns `:noreply` or `:halt`.

**tell / poll.** The original ref stays `:pending` through every attempt, including the gap between attempts. It never returns `:not_found`. The final outcome is stored under the original ref.

**Completion recipient.** Exactly one `{:gen_agent, :completion, name, ref, outcome}` message, sent for the final attempt only.

**Repeated retries.** No built-in cap. Each failure calls `handle_error` again, and agent state owns the retry budget.

**Ordering.** The retry keeps its current priority over the mailbox. Queued requests wait and keep FIFO order.

## Cancellation, interrupt and timeout
- **Watchdog `:timeout` and `{:task_crashed, _}`:** both can be retried. The watchdog is per attempt, because entering `:processing` re-arms it. A total deadline across attempts is out of scope.
- **Interrupt (`interrupt/1` or `interrupt_request(ref)`):** ends the request for the caller, who gets `{:error, :interrupted}`. If `handle_error` still returns `{:prompt}`, it becomes an unowned `:self_chain`, which is today's behavior.
- **Halt:**
  - `handle_error` returning `{:halt}` delivers the current error to the caller.
  - If the agent halts while a retry is pending (for example a buffered `notify` halts during `drain_pending_events`), the retry follows the same on-halt rules as queued work. It survives and runs after `resume` for asks, plain tells and `on_halt: :queue`. For `on_halt: :fail` it fails with `{:error, :halted}`.
- **`cancel_request(ref)` on a pending retry while halted:** treated like a queued tell. Returns `{:ok, :cancelled}`, sends completion `{:error, :cancelled}`, and emits `turn.cancelled`.
- **Caller of an in-flight ask exits:** no monitor is added, matching what in-flight asks do today, so the late reply is simply dropped.
- **Task supervisor unavailable:** the existing behavior stays. `reject_dispatch/4` discards the retry and the caller gets `:task_supervisor_unavailable`.
- **Retry rejected by the self-chain byte cap:** the caller gets the original failure reason. The overload still goes to `handle_error`, but as an unowned follow-up.
- **`pre_turn` skip, halt or invalid on a retry:** goes through `record_error` with the original kind, so the caller sees the `:pre_turn_*` reason.

## Telemetry and refs
- Every attempt reuses the caller's ref. That covers the callbacks' `request_ref`, `checkpoint_session`, `interrupt_request`, `status`, and `runtime_snapshot`.
- `turn.*` and `prompt.*` events gain `attempt` metadata (1-based). The origin stays `:ask` or `:tell`, not `:self_chain`.
- `format_status` already redacts the self-chain slot.

## Needs a design decision
1. **Changing what `{:prompt}` means in `handle_error/3`** (recommended) versus adding a new opt-in `{:retry, p, s}` return. Changing `{:prompt}` matches the callback docs ("useful for retry") but breaks `server_test.exs:710` and any users who rely on the early error. It needs a `feat!` and a MIGRATION entry.
2. **Reusing the ref with `attempt` metadata** (recommended) versus a fresh ref per attempt plus `retry_of`. Reuse breaks the documented rule that each ref has one start and one terminal event; it would become one pair per `(ref, attempt)`.
3. **Interrupt ends the request for the caller** versus letting it be retried.

Everything else follows mechanically from these three choices.

## Deterministic regression cases
Each uses scripted backends with `assert_receive`/`refute_receive` on notify messages and telemetry, no sleeps:
1. ask: error then success returns `{:ok, "succeeded on retry"}`, with `handle_error` called once.
2. tell: `poll` returns `:pending` during the retry, then `{:ok, :completed, _}` under the original ref.
3. `tell_with_completion`: exactly one completion message, the success, and `refute_receive` for any error completion.
4. Error, error, success: one reply, with `attempt` 1, 2 and 3 in telemetry. A budget-exhausted variant delivers the last reason.
5. Retry, then `{:halt}` from `handle_error`: the caller gets the second error.
6. `interrupt_request(ref)` on the retry attempt: the caller gets `:interrupted`, and the follow-up runs with origin `:self_chain`.
7. Watchdog `:timeout`, then the retry succeeds.
8. Task crash, then the retry succeeds.
9. Buffered notify halts during the drain: `poll` returns `:pending`, `resume` delivers the result, and an `on_halt: :fail` recipient gets `:halted`.
10. A queued ask behind the retry gets its own result, in order.
11. `handle_response` returning `{:prompt}` still produces an unowned `:self_chain` turn.
12. The existing unavailable-supervisor test passes unchanged.
13. A retry over the byte cap gives the caller the original reason.
14. `cancel_request` on a pending retry while halted returns `{:ok, :cancelled}` and sends the cancelled completion.

I read the source and tests only and ran nothing.

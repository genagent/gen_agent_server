I'm requesting changes, mainly because of one surface the issue didn't mention. The shared HTTP MCP listener now accepts waits of up to 600 s, but it only allows a 10 s request. The core waiter logic in `Invocations` is correct, and the other acceptance items are met by the code. I couldn't run anything, so the build and test item is unverified.

## 1. Acceptance

| Item | Status | Evidence |
|---|---|---|
| A waiter gets the result on complete, fail or cancel | Met | `lib/gen_agent_server/invocations.ex:463-470` replies to every waiter for the ID inside `record_completion/2`. Cancel runs `collect_available` (`:257`), so waiters are woken there too. Tests: `test/gen_agent_server_cancellation_test.exs:111` (all three outcomes, polled) and `:133` (cancel). |
| A waiter gets `{:ok, :pending}` after `wait_ms` | Met | `invocations.ex:189` sets the timer and `:378-395` replies. If the timer fires after completion already replied, `Map.pop` returns `nil` and nothing is sent twice. Test: `cancellation_test.exs:143`. |
| Two waiters on one ID both get the result | Met | Waiters are stored per ID, one entry per call ref (`invocations.ex:191-197`). Test: the two tasks at `cancellation_test.exs:115-117`. |
| `invoke` and `result` aren't blocked while a caller waits | Met | The waiting call returns `{:noreply, ...}` (`invocations.ex:199`). Test: `cancellation_test.exs:148-153`. |
| `wait_ms` of 0 or absent is unchanged; bad values give `:invalid_wait` before lookup | Met | `result/2` passes `[]`, which becomes `wait_ms: 0` and takes the old reply path (`invocations.ex:36, 187, 201`). Validation happens before `call_instance` (`:42-49`). Test: `cancellation_test.exs:162-165`. |
| Remote ops task and remote CLI don't time out before `wait_ms` | Met | `lib/mix/tasks/gen_agent_server.ops.ex:140-145` and `lib/gen_agent_server/remote.ex:83-92`. Tests: `test/gen_agent_server_result_rpc_test.exs` and `test/gen_agent_server_remote_test.exs:74`. |
| Format, compile, Credo, tests, docs and extension matrix pass | Can't verify by reading | |

## 2. Defects

1. **The shared MCP listener's `result` tool accepts waits it can't serve.** `extensions/mcp/lib/gen_agent_server/mcp/shared/tools.ex:87` builds the schema from the catalogue, so `wait_ms` up to 600_000 is now exposed. `Shared.run` passes it straight to `Ops.call` (`extensions/mcp/lib/gen_agent_server/mcp/shared.ex:73`).
   - The listener has `request_timeout: 10_000` and `max_concurrency: 8` (`shared.ex:39,47`), so any wait over about 10 s fails at the transport. Eight waiting clients would also take every request slot.
   - `ask` on this listener is deliberately capped at 5000 ms (`shared.ex:88-97`, `tools.ex:124`).
   - **Fix:** in `Shared.Tools.Result`, set the schema's `wait_ms` maximum to 5000 with a matching description. In `Shared.run`, reject `"result"` calls with `wait_ms` outside 0..5000, as `ask` does. Add a shared-listener test for an over-limit `wait_ms`.

2. **The catalogue doesn't publish the upper bound.** `lib/gen_agent_server/ops.ex:122-126` gives `wait_ms` only `minimum: 0`. The `limit` parameter next to it adds its range to the schema (`ops.ex:93`). MCP clients therefore see no maximum and only find out through an `invalid_wait` error.
   - **Fix:** `|> Map.put(:schema, %{"minimum" => 0, "maximum" => 600_000})`, then assert the maximum in `extensions/mcp/test/gen_agent_server_mcp_test.exs:124-128`.

3. **CLI messages weren't updated for `--wait`.**
   - The usage string at `lib/gen_agent_server/cli.ex:121` and at `lib/mix/tasks/gen_agent_server.remote.ex:12` still reads `result ID`.
   - `:invalid_wait` falls through to `"GenAgent request failed: :invalid_wait"` (`cli.ex:128`).
   - `error_message(args, :not_found)` only matches `["result", id]` (`cli.ex:101`). `result ID --wait N` on an unknown ID prints "requested item not found" instead of naming the invocation.
   - **Fix:** add `[--wait MS]` to both usage strings. Add `{["result", id, "--wait", _], instance}` to the `:not_found` match. Add an `error_message(_, :invalid_wait)` clause such as `"--wait must be an integer from 0 to 600000"`.

4. **`result/3` crashes on non-keyword options instead of returning an error.**
   - `GenAgentServer.result/3` (`lib/gen_agent_server.ex:163`) has no `is_list(opts)` guard. `Invocations.result/3` (`invocations.ex:40`) calls `Keyword.get` on it directly, so a map raises.
   - Unknown keys are silently ignored. `invocations/2` in the same module returns `{:error, :invalid_options}` for both cases (`invocations.ex:57-64`).
   - **Fix:** use the same `cond` guard as `invocations/2`. Return `{:error, :invalid_options}` when `opts` isn't a keyword list or has keys other than `:wait_ms`.

5. **On expiry, a finished turn can still be reported as pending.** `handle_info({:wait_expired, ...})` (`invocations.ex:378`) replies `{:ok, :pending}` without draining the inbox. A turn that finished within the last `poll_interval_ms` is still reported pending at the deadline.
   - **Fix:** call `collect_available(state)` at the start of the expiry handler. If the waiter is still registered afterwards, reply pending; if collection completed it, the waiter has already been answered. Treat an inbox error the way `:collect` does.

## 3. Not asked for by the issue

- `handle_call({:result, id}, ...)` is kept at `invocations.ex:175`, but no caller sends the two-element tuple any more. It's dead code; remove it, or note that it's kept for compatibility.
- `Remote.timeout_for` now strips any `--instance NAME` prefix (`remote.ex:83`), not just the one in front of `ask`. This is needed for `--instance X result ID --wait N`, and `ask` behaves as before, so it's a fine change. It just goes beyond what the issue named.
- The MCP test at `extensions/mcp/test/gen_agent_server_mcp_test.exs:113` was renamed and widened. That follows from the schema change.

REQUEST CHANGES

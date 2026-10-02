APPROVE

I read the diff against `server.ex` and checked each documented claim. The tests were not run: `deps` and `_build` are missing from the worktree, so the implementer's "could not run" is accurate. I'm approving on code reading alone.

**Doc claims checked against `server.ex`**
- **Server-process execution** (`strategy.ex:14-17`): correct. `call_strategy` matches strictly on `{:ok, ops, state}` at `server.ex:989-991`. `safely_callback` turns any raise or bad match into `{:stop, {:callback_failed, ...}}` (`server.ex:200-222`). Every callback runs inside a Server callback, so a blocking one blocks that server.
- **`init/1` error shape** (`strategy.ex:107-112`): correct. `server.ex:149` and `:186` turn `{:error, reason}` into `{:stop, reason}`. The type now includes `| {:error, term()}`, and the signature is otherwise unchanged.
- **`handle_error` fallback** (`strategy.ex:122`): correct. It logs a warning and leaves state unchanged (`server.ex:481-496`). It only applies to an active dispatch, which the doc doesn't say, but that's minor.
- **`handle_start_rejected` fallback** (`strategy.ex:125`): correct. `:cont` when the callback is missing (`server.ex:565-575`).
- **`handle_dispatch_rejected` fallback** (`strategy.ex:128`): correct. `reject_dispatch` replies to the token with `{:error, {:dispatch_rejected, ...}}` (`server.ex:583-601`).
- **`handle_notify`, `handle_agent_down` and `handle_status` fallbacks** (`strategy.ex:139-145`): correct (`server.ex:337-350`, `:416-427`).
- **Status merge** (`strategy.ex:145`): correct. It uses `Map.merge(base, extra)`, so strategy keys win (`server.ex:340`).
- **Token correlation** (`strategy.ex:83-85`): correct. `handle_response/3` receives no token, and the implementer left the existing `handle_cancel` doc alone.

**Tests**
- `InitErrorStrategy` works without `trap_exit` because `Server.start_link` uses `GenServer.start` and links only on success (`server.ex:43-50`). The result is `{:error, :bad_configuration}`.
- `StatusOverrideStrategy` overrides the base `:session` key. That is a real behavioral gap, not a restatement of the docs.
- The `defmodule`s sit at the top of the test module, before the helper functions.

**Scope**
- Only `strategy.ex` and `server_test.exs` changed. `server.ex` and the main module are untouched, and no callback signature changed.

**Gaps**
- `handle_status` and `handle_notify` have no fallback test. That fits the "only behavioral gaps" constraint, so I'm not requesting it.
- Confirm `mix test` passes in CI, since I couldn't run it. If the new tests fail, it would most likely be a missing callback in the test strategies or a registry-name clash.
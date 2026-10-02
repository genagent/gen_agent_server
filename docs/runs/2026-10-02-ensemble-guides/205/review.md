APPROVE

I read the diff against `server.ex` and the existing tests. I did not run the suite. The implementer could not run it, and the host's validation (171 tests, format, Credo, docs, Dialyzer) is the direct evidence for that.

**Doc claims checked against code**
- `strategy.ex` moduledoc, synchronous execution: `call_strategy` at `server.ex:989-991` is a strict `{:ok, ops, state}` match. Every handler runs inside `handle_call`, `handle_cast` or `handle_info`, and `safely_callback` (`server.ex:~190-200`) turns a raise or bad shape into `{:stop, {:callback_failed, ...}}`. Accurate.
- `init/1`: `init_impl` returns `{:stop, reason}` on `{:error, reason}` (`server.ex:~188-189`), and `start_link` passes `{:error, reason}` through. The widened callback type is correct.
- `handle_error`: it is skipped when the token is not pending (`server.ex:476-479`). When the callback is missing, the server logs "unhandled" and leaves state unchanged (`server.ex:491-496`).
- `handle_start_rejected`: when the callback is defined, the batch halts. When it is missing, the batch continues (`server.ex:564-577`).
- `handle_dispatch_rejected`: the batch halts (`server.ex:560`). The server closes the token as a dispatch error if the callback is missing or leaves the token pending (`server.ex:581-605`).
- `handle_notify`, `handle_agent_down` and `handle_status` fallbacks match `server.ex:337-355` and `416-427`. The status merge is `Map.merge(base, extra)`, so extras win (`server.ex:343`).
- Token correlation: `handle_response` is called with `[bare_agent, response, state]` and no token (`server.ex:461-470`). Accurate.

**Tests**
- The two new tests cover the real gaps: `init/1` returning `{:error, reason}`, and a status key overriding a base key. The tests directory had no existing coverage for either.
- Callback raises and unexpected return shapes are covered by `format_status_test.exs` and the strategy tests. The unhandled-error log, `:unsupported` cancel and dispatch-rejection fallbacks are covered in `format_status_test.exs`, `cancel_test.exs` and `dispatch_rejection_test.exs`.
- The tests add no assertions that only restate the docs.

**Scope**
- Only `strategy.ex` and `server_test.exs` changed. There are no signature or server behavior changes, and the `@type`/`@callback` widening for `init/1` is the requested documentation fix.

**Nits, not blocking**
- `strategy.ex`, `handle_start_rejected` doc: the callback only fires for `:start` ops that fail during op processing. A start spec returned from `init/1` that fails stops the server instead (`apply_start_specs`, `server.ex:~195-204`). A short note would prevent confusion.
- The `handle_response` doc does not mention that it is skipped when its token is no longer pending. The moduledoc Tokens section already says this, so it is not wrong.
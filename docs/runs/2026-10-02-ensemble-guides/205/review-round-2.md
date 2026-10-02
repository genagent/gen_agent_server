REQUEST CHANGES

I read `server.ex` and the existing tests but did not run the suite. The docs match the server code. The new init-error test will most likely kill the test process.

**Blocking**

- `server_test.exs:81-84`: The init-error test calls `GenAgentEnsemble.start_link/1` without `Process.flag(:trap_exit, true)`. `Server.init/1` returns `{:stop, reason}` (`server.ex:190`), so the server exits with a non-normal reason. That exit signal reaches the linked test process, and the test dies instead of asserting. Every other test that makes `start_link` fail at init sets the flag first, for example `consensus_test.exs:313,331`, `debate_test.exs:261,276` and `switchboard_test.exs:130`. Add the flag to this test. The implementer did not run it, so this is untested.

**Non-blocking**

- `strategy.ex` `handle_start_rejected` doc: The doc says what happens when the callback is omitted (the batch continues, `server.ex:573`). It does not say that defining the callback halts the rest of the batch (`server.ex:564-571`). That is the more surprising behavior for an author. Similarly, `handle_dispatch_rejected` also halts the batch (`server.ex:556`), and the server still closes the token if the strategy does not reply (`server.ex:594-597`). The doc as written is accurate but incomplete.
- `strategy.ex` `handle_error` doc: The fallback is described correctly. The doc omits that the callback is skipped entirely when the token is no longer pending (`active_dispatch?`, `server.ex:478`).
- Acceptance asks for tests covering each case. The implementer added only two tests: init error and status override. I did not check whether existing tests already cover the optional-callback fallbacks. The issue itself says to add tests only for gaps, so this is acceptable if existing coverage is confirmed.

**Verified correct**

- Callbacks run synchronously inside the server. A raise or bad return shape crashes via `call_strategy`'s strict match (`server.ex:989-992`) and `safely_callback` (`server.ex:214-222`).
- `init/1` `{:error, reason}` becomes `{:stop, reason}` (`server.ex:171`).
- `handle_status` is merged over the base map with `Map.merge(base, extra)`, so extras win (`server.ex:309`).
- Fallbacks are correct for `handle_error`, `handle_agent_down`, `handle_notify` and `handle_status`.
- The scope is correct. Only `strategy.ex` and the test file changed. No signatures or server behavior changed, and the draft-PR files are untouched.
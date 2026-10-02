APPROVE

I checked the guide and tests against the current core source. I could not run the tests, because `mix test` fails here with missing deps (`telemetry`, `dialyxir`, `credo` aren't fetched, and there is no `_build`). The assessment below comes from reading the code, not from a passing run.

**Checked against the code**
- **Overload handling:** `tell/2` returns `{:error, {:overloaded, info}}` on admission failure (`lib/gen_agent/server.ex:908-938`). The new `submit/2` returns that error instead of matching `{:ok, ref}`.
- **Limit semantics:** `overload_reason/6` (`server.ex:1002-1008`) rejects when `count >= max_count` or when the incoming size exceeds the remaining byte budget. The guide's "active turn is excluded" claim holds (`server.ex:344`, `:871`). The byte unit is `:erlang.external_size/1`. The 1,000 and 1,048,576 defaults match `server.ex:25-26`.
- **Configurable limits:** `GenAgent.start_agent` accepts `:max_pending_prompts` and `:max_pending_prompt_bytes` (`lib/gen_agent.ex:560-581`). `Keyword.take` in `Pool.start` forwards them correctly.
- **Failure identity:** `pre_turn/2` runs before dispatch and persists `agent_state` (`server.ex:1103-1106`). Backend `{:error, reason}` reaches `handle_error/3` unwrapped (`server.ex:1260`, `:1740`). Recording `state.task` in `pre_turn` and clearing it in both handlers is sound.
- **Metadata polling:** `runtime_snapshot/1` exposes `phase`, `pending_prompts`, `pending_notifications` and `self_chain_pending` (`server.ex:609-615`). `do_wait` uses exactly those fields, so it no longer copies results.
- **Atomic dispatch:** `:atomics.add_get/3` gives each concurrent caller a distinct index. The "rejections also consume a position" note is accurate, since the increment happens before `tell`.
- **Test fixture:** the backend runs in a `Task.Supervisor` task (`server.ex:1156`). Blocking in `hold:` therefore does not block `runtime_snapshot` calls on the agent, so the controlled-hold tests are valid.
- **Scope:** only `guides/patterns/pool.md` and `test/guides/pool_test.exs` changed. There are no core changes.

**Non-blocking notes**
- `guides/patterns/pool.md` (`handle_error` section): a queued request cancelled via `cancel_request/3` runs no lifecycle callbacks (`lib/gen_agent.ex:~650`). It therefore never reaches `handle_error/3` and is absent from `results/1`. The guide says failures "count toward the worker's total" without this caveat. Consider one sentence on it.
- `test/guides/pool_test.exs`, the "metadata snapshots" test: it uses `:erlang.trace_pattern` and `:erlang.trace` on `GenAgent.status/1`. That is global and a little fragile, but it is cleaned up in `on_exit` and the test is `async: false`.
- Run `mix deps.get` and then `mix test test/guides/pool_test.exs` before the PR to confirm the six tests pass. That is the caller's step under the stated constraints.
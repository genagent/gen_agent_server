**APPROVE**

I checked the change against `lib/gen_agent/server.ex` by reading the code only. I did not run the tests because this session was read-only.

**The narrowed overload clause is correct (`guides/patterns/supervisor.md`, the `handle_error` clause for `{:overloaded, %{queue: queue}}`).**
- The server only builds `{:overloaded, %{queue: q, limit: :count | :bytes, ...}}` itself, in `overload_reason/6` (`server.ex:1001-1021`). `q` is `:prompts`, `:notifications` or `:self_chain`.
- When a worker report arrives during a turn, it is buffered. On the next drain, `handle_event` returns `{:prompt, ...}` and `enqueue_prompt(..., :event, ...)` adds it to the queue (`server.ex:1719-1730`). If the queue is full, `reject_generated_prompt/3` calls `handle_error/3` with the `:prompts` reason (`server.ex:1737-1748`).
- The drain runs after the in-flight extra turn's `pre_turn/2`, which set `synthesis_turn: false` because the phase was still `:collecting`. So the rejection reaches `handle_error` with phase `:synthesizing` and `synthesis_turn: false`, which is exactly what the new clause matches.
- A user ask or tell that is rejected at the queue goes back to the caller as `{:error, reason}` and never reaches `handle_error` (`server.ex:903-911`, `814`). So the clause cannot be triggered by an extra user turn being rejected.
- A provider overload without a `queue:` key now falls through to `{:noreply, state}`, as the guide says.

**The tests cover the right cases.**
- The provider-overload variant sends `{:overloaded, %{provider: :fixture}}` from the queued extra turn, then checks that synthesis still runs and reaches `:done` with no error. The old `{:overloaded, _}` clause would have failed this test, so it really checks the narrowing.
- In the full-queue test, `max_pending_prompts: 1` with one queued tell makes `count >= max_count`, which produces the `:prompts`/`:count` overload. The test then checks `:failed`, halted, `synthesis_turn == false`, and that the workers and watcher were cleaned up.
- The test comment says halting keeps ordinary queued tells. That is correct: `fail_halt_aware_queued/1` (`server.ex:1671-1691`) only drops `{:tell, _, :fail}` entries. The implementer's report said the test checks that halting *cancels* the queued turn. That is wrong, but the guide and the test both describe the actual behaviour.

**The guide's claims match the server.**
- "count or byte limit" matches the `:count`/`:bytes` limits in `overload_reason/6`.
- Rejection "before dispatch" means before `pre_turn/2` runs, which is correct because the prompt is rejected at enqueue.
- Cleanup happens through `finish/3` sending `:finish` to the watcher.

**All five issue items are addressed.**
- Workers are stopped by the watcher on every terminal path and when the coordinator exits, and worker names include the run, so the coordinator name can be reused straight away.
- The worker backend is now the `worker_backend:` option instead of a hard-coded Anthropic backend.
- Both modules now have fallback `handle_response`/`handle_error` clauses, including the terminal phases in `Research.Agent`.
- Collection is bounded by worker monitors plus `collect_timeout`, and rejected notifications are retried.
- The modules are renamed to `Fanout.*` and the worker option to `coordinator:`.
- Each case has a test.

**Minor points, none blocking:**
- `supervisor.md`, overload `handle_error` clause: the `:self_chain` part of the guard can never match in this coordinator. Synthesis is only ever queued from `handle_event` as an `:event` prompt, and the coordinator never returns `{:prompt, ...}` from `handle_response` or `handle_error`. It does no harm.
- The clause matches on the shape of the error, not on where it came from. A backend that returned its own `{:overloaded, %{queue: :prompts}}` would still be treated as a rejected synthesis. That is unlikely, and the guide's wording is accurate for the server's own errors.
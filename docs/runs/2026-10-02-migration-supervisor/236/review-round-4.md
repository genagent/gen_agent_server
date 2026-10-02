APPROVE

I traced the rejection path in the server code and ran the focused tests: 19 passed. I also ran the supervisor test file 6 more times and all 13 tests passed each time. `mix format --check-formatted` and `git diff --check` are both clean.

**Checks**

- **The new clause fixes the stuck state.** When a worker report is buffered, `apply_pending_event` puts the synthesis prompt in the mailbox via `enqueue_prompt` (`lib/gen_agent/server.ex:1723-1729`). If the queue is full, that fails with `{:overloaded, %{...}}` (`server.ex:1002-1021`). `reject_generated_prompt` then calls `handle_error/3` before `pre_turn/2` has run, so `synthesis_turn` is still `false` (`server.ex:1736`). The new clause at `guides/patterns/supervisor.md` (the `{:overloaded, _}` / `synthesis_turn: false` clause) catches this case. It calls `finish/3`, which sends `:finish` to the watcher and returns `{:halt, ...}`, and `transition_to_halted` applies that halt.
- **The clause also covers a full self-chain slot.** `accept_self_chain` sends its rejections through the same `reject_generated_prompt` path (`server.ex:995-999`).
- **The test reproduces the reported case.** With `max_pending_prompts: 1`, one extra turn is running and another is queued, so the mailbox is full. The buffered `notify_ack` makes the rejection happen during drain. Without the new clause, the catch-all would return `{:noreply, ...}` and the `await` for `:failed` would fail.
- **The test asserts the cleanup the task asked for.** It checks that the coordinator is halted with an `{:overloaded, _}` error, `synthesis_turn` is false, the workers are unregistered, the watcher is dead, and a worker session was terminated. It also releases the queued extra turn after `resume` and checks the state does not change.
- **The guide paragraph matches the code.** It describes the overload failure and the cleanup accurately.
- **Scope is unchanged.** The research guide changes and the 18 earlier tests are still in place.

**Non-blocking**

- **The new clause can match a backend error from an extra user turn.** It matches any `{:overloaded, _}` reason while the phase is `:synthesizing`. If a backend reported provider overload as `{:error, {:overloaded, _}}` during an extra ask/tell, the run would fail. The guide says ordinary turn errors do not end the workflow, so that would contradict it. You could narrow the clause to the server's own reason shape: `{:overloaded, %{queue: q}} when q in [:prompts, :self_chain]`.
- **The guide's wording is a little narrow.** It says "If the prompt queue is full". The same clause also handles rejection because of the `max_pending_prompt_bytes` limit. Saying "if the prompt queue rejects synthesis (count or byte limit)" would be more precise.
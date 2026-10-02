REQUEST CHANGES

I checked every claim in the change against `lib/gen_agent.ex` and `lib/gen_agent/server.ex`. I did not run the tests: plan mode limits me to read-only actions, so the "53 guide tests pass" result comes only from the implementer's report.

**Blocking**

1. `guides/patterns/heartbeat.md:174` (and the explanation at `:56-61`): the guide's `Heartbeat.Ticker` calls `:gen_statem.cast(state.pid, {:notify, :tick})`. That is the server's internal message format (`lib/gen_agent/server.ex:632,638`). The public API never documents it; only the runtime's own tests use it (`test/gen_agent/server_test.exs:58`). A pattern guide that users copy should not depend on a private wire format, and the guide even tells readers to "keep the guide tests when adapting it." The orphan/replacement problem can be fixed with the public API instead:
   - Before each tick, check `GenAgent.whereis(name) == state.pid`, then call `GenAgent.notify(name, :tick)`.
   - If the name now points to a different process or to nothing, stop the ticker.
   - The monitor's `:DOWN` message still ends the ticker when the agent exits. The only gap left is the instant between the lookup and the send, and a gap that small is acceptable for a guide.

   The replacement-agent test stays valid with this change.

**Non-blocking**

2. `test/guides/heartbeat_test.exs:63-68` and `test/guides/watcher_test.exs:60-65`: `halt/1` uses `:sys.replace_state` to write `halted: true` straight into the server's internal `Data` struct. The Heartbeat guide already describes `{:halt, state}` from `handle_event` as a variation. Either test halting through a public path, or add a comment saying the test depends on the internal struct shape.
3. `test/guides/heartbeat_test.exs:160`: `send(ticker, :tick)` goes to a ticker that the test has already confirmed is dead, so `refute_receive` on the next line proves nothing. The "no duplicate ticks" check that actually works is the telemetry block at `:162-176`. Remove the dead send, or replace it with a check that `Process.alive?(ticker)` is false.
4. `guides/patterns/heartbeat.md:170-183`: `Heartbeat.Ticker.handle_info/2` has no catch-all clause, so any unexpected message crashes it. The child is `:temporary`, so the ticker would then stop for good. Add `def handle_info(_msg, state), do: {:noreply, state}`.
5. Scope: the issue's last item also says the Watcher and Heartbeat scenario tests (`test/scenarios/watcher_scenario_test.exs`, `test/scenarios/heartbeat_scenario_test.exs`) have drifted from their guides. The new guide tests compile the guide modules themselves, which covers the intent. However, the scenario files are unchanged, and the report should say so explicitly alongside the #236 carve-out.

**Claims verified as correct**

- **Heartbeat failure handling:** the batch is held in `in_flight` until the turn succeeds. A rejection of a prompt generated while halted or from a deferred event goes through `reject_generated_prompt` to `handle_error/3`, with `in_flight` already set (`server.ex:1063,1729,1737-1749`), so the batch is restored. `handle_error` returns `{:noreply, ...}`, so there is no immediate retry loop.
- **Watcher failure handling:** popping the newest pending event when `active` is nil matches where rejections happen (enqueue in halted idle, or the deferred drain after `handle_response` has cleared `active`). `pre_turn` takes events from the head before dispatch, and the `reject_dispatch` path runs after `pre_turn`, so in that case `active` is set (`server.ex:1103-1112`).
- **Halted ticks:** the issue's correction holds. While a batch is in flight, or when there are fewer than `min_batch` observations, a tick queues nothing. The new `in_flight` clause also stops repeated ticks from queueing duplicate batches. The rewritten self-halting variation describes this accurately.
- **Admission statements:** `notify/2` always returns `:ok` and rejections emit `[:gen_agent, :input, :rejected]` (`gen_agent.ex:749-762`, `server.ex:964`). `notify_ack/3` covers admission only (`gen_agent.ex:764-781`). The count and byte limit option names match `server.ex:146-155`. The descriptions of `runtime_snapshot/2`, `tell_with_completion/4` and `interrupt_request/3` match the code.
- **Scope:** no core runtime, Supervisor scenario or other guide files were touched. The Ticker is now a `GenServer` with `restart: :temporary`, so it can go directly into a supervision tree.

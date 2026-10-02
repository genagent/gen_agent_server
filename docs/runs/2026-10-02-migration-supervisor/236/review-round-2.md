REQUEST CHANGES

I read the guides, the tests and the relevant GenAgent source myself and did not rely on the implementer's report. Most of the change holds up, but one claim the guide now makes is false under a reachable ordering.

**Blocking**

1. **A queued user prompt can be taken as the synthesis answer** (`guides/patterns/supervisor.md:160-163`, `:203-204`, and the claim at `:443`).
   - **How the ordering arises.** The synthesis prompt is returned from `handle_event/2`. If a worker report arrives while another turn is running, the report is buffered. After that turn ends, `drain_pending_events/1` puts the synthesis prompt at the back of the prompt queue as an `:event` turn (`lib/gen_agent/server.ex:1696-1731`). It is not a priority self-chain like the one at `server.ex:328-333`.
   - **Failure case.** During `:collecting`, the user sends `tell "a"`, which is now running, and `tell "b"`, which is queued. The last worker report arrives while "a" runs. When "a" finishes, phase becomes `:synthesizing` and the synthesis prompt is queued behind "b". Turn "b" then runs and its response matches the `:synthesizing` clause, so `final_output` is the reply to "b" and the coordinator halts as `:done`. The real synthesis turn runs later and is ignored by the terminal clause. If "b" errors instead, `handle_error` in `:synthesizing` fails the whole run.
   - **Effect on the guide.** The guide says "Extra ask/tell turns are ignored by the phase logic", which is false in this case. The new handler clauses fix the crash the issue reported, but this mix-up is a new wrong-result bug.
   - **Suggested fix.** Mark the synthesis turn explicitly, for example by matching the stored synthesis prompt in `pre_turn/2` (`lib/gen_agent.ex:348`) and setting a flag. Treat a response or error as synthesis only when that flag is set. Add a test with one in-flight extra turn and one queued extra turn while the last report arrives.

**Non-blocking**

2. **Stale reference** (`guides/patterns/supervisor.md:490-492`). The "Heterogeneous workers" variation still points to "the coordinator's `spawn_workers` function", which was removed. Worker startup now happens in `Fanout.Watcher.handle_call({:spawn, ...})`.
3. **Weak rerun assertion** (`test/guides/supervisor_test.exs`, success test). `if GenAgent.whereis(name) == nil, do: start(name: name)` would quietly skip the rerun if the stop had not finished. `GenAgent.stop/1` is synchronous, so assert `GenAgent.whereis(name) == nil` and start the new coordinator without the `if`.
4. **Possible 5-second stall, worth one sentence in the boundaries section.** The coordinator traps exits (`server.ex:130`) and blocks in `GenServer.call(watcher, {:spawn, ...}, :infinity)`. If `GenAgent.stop/1` on the coordinator lands during worker startup, the shared DynamicSupervisor waits on the coordinator's shutdown while the watcher waits on that same supervisor in `start_child`. This clears when the shutdown timeout kills the coordinator, so it is a stall, not a permanent deadlock.

**Claims I checked and confirmed**

- All five original problems exist in the pre-change guide.
- `:backend` is removed from the options before `init_agent/1` (`lib/gen_agent.ex:551-564`), so the explicit `worker_backend:` option is justified.
- `notify/2` always returns `:ok` even when the event is later rejected, and `notify_ack/3` reports admission (`lib/gen_agent.ex:754-781`). Retrying through `notify_ack` in the watcher is sound, and the docs describe its limits accurately.
- `handle_response` runs inside the coordinator process (`server.ex:1767`), so the watcher's `Process.monitor` is attached to the right pid.
- Per-run worker names plus the `run` check in `handle_event` rule out the stale-name collision on rerun and reject reports from an old run.
- The watcher stops started workers on every terminal path: finish, partial startup failure, coordinator stop or crash, and the deadline.
- **Research.Agent:** its only idle, unhalted states are the terminal phases, because the middle phases self-chain and self-chains take priority. The new `:done`/`:failed` clauses therefore cover the gap the issue describes.
- **Scope:** the change touches only the two guides and two new tests. The tests use the same extract-and-compile approach as `test/guides/watcher_test.exs`.
- `mix format --check-formatted` passes on both new test files.

I did not run the test suite. This session was read-only, so the "16 tests passed" result comes only from the implementer's report.
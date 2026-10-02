Nothing edited. Line numbers in the issue are stale against this checkout (`26bd542`). The file:line references below are the ones I re-checked.

## Claims that still hold

1. **Heartbeat drops the batch on a failed turn.**
   - The tick clause returns `{:prompt, prompt, %{state | observations: []}}` (`guides/patterns/heartbeat.md:107`).
   - The guide defines no `handle_error/3`. The default is `{:noreply, state}` (`lib/gen_agent.ex:429`).
   - A failed summary turn therefore loses the batch.
2. **Watcher records nothing on failure.**
   - The diagnosis and welcome prompts return state unchanged (`guides/patterns/watcher.md:99,104`).
   - There is no `handle_error/3`. Actions are added only in `handle_response` (`:114-117`).
3. **The "harmless, but noisy" statement is inaccurate** (`heartbeat.md:200-201`).
   - A halted agent still runs `handle_event`. A `{:prompt, ...}` return is queued, and `notify_idle_prompt` does this when `halted` is true (`lib/gen_agent/server.ex:1054-1062`). The queue drains on `resume` (`server.ex:699-701`).
   - The correction in the issue is right. The tick clause clears `observations`, so later ticks with fewer than `min_batch` new observations queue nothing.
   - If the queue is full, `notify_ack` returns `{:error, {:overloaded, _}}` (`lib/gen_agent.ex:768-777`).
4. **The ticker is not tied to the agent.**
   - `Task.start_link` links it to the caller (`heartbeat.md:130`).
   - `GenAgent.stop` only calls `DynamicSupervisor.terminate_child` (`lib/gen_agent.ex:930-935`). The ticker keeps casting.
   - `notify/2` is a cast that always returns `:ok` (`lib/gen_agent.ex:760-762`), so the ticker never fails.
   - A later agent started under the same name receives ticks from the old ticker and the new one.
   - There is no `child_spec/1`.
5. **Both guides have stale notification text.**
   - Heartbeat says buffered ticks are never dropped (`heartbeat.md:43-46`).
   - Watcher says the "mailbox can fill up" (`watcher.md:159-162`) and still carries the "pre-v0.2" caveat (`:35-47`).
   - Pending inputs are bounded (`:max_pending_notifications` and `:max_pending_prompts`, both default 1000, with byte limits too; `lib/gen_agent.ex:497-506`, `server.ex:25-28`).
   - `notify/2` drops silently on overflow and emits `[:gen_agent, :input, :rejected]` telemetry.
   - A deferred event whose generated prompt cannot be queued is reported to `handle_error/3` as `{:overloaded, info}` (`lib/gen_agent.ex:773-777`).
   - Neither guide mentions `notify_ack/3`. `tell_with_completion` and `interrupt_request` appear in no pattern guide. `notify_ack` and `runtime_snapshot` appear only in `switchboard.md` and `pool.md`.
6. **No guide-compiling tests exist for these two guides.**
   - `test/guides/` has only `pool_test.exs`, `retry_test.exs`, `switchboard_test.exs` and `workspace_test.exs`.
   - The heartbeat and watcher scenario tests define their own agents. The heartbeat timer test uses a `Task.async` loop, not `Heartbeat.Ticker` (`heartbeat_scenario_test.exs:201-219`).

## Overlaps with #236, left alone

The Supervisor scenario drift and its leaked workers (`test/scenarios/supervisor_scenario_test.exs`) are #236. I would not touch that file. The #244 acceptance line "tests cover each case above" cannot be met for that bullet without overlapping #236. Report it as out of scope. Heartbeat and Watcher tests are in scope.

## Plan: smallest change

**1. `guides/patterns/heartbeat.md`**
- **Agent state.** Add `in_flight: []` and `failures: []`. The tick clause moves `observations` into `in_flight ++ [batch]`, clears `observations`, and returns `{:prompt, ...}`.
- **`handle_response`.** Pop the head of `in_flight`. Prompts run in FIFO order, so this is correct.
- **New `handle_error/3`.** Pop the head batch and put it back in front of `observations` (`batch ++ observations`). Record `{reason}` in `failures`. This covers `{:overloaded, _}`, since a rejected prompt never ran. Return `{:noreply, state}`, so there is no immediate retry loop.
- **Ticker as a GenServer with `child_spec/1`.**
  - `init` resolves `GenAgent.whereis(name)` and monitors that pid.
  - It uses `Process.send_after` for the interval.
  - Before each tick it checks `GenAgent.whereis(name) == pid`. It sends `GenAgent.notify_ack` and ignores or logs an `{:error, {:overloaded, _}}` result.
  - It stops with `:normal` on `:DOWN`. This leaves no orphan after `GenAgent.stop`, and a restarted agent gets no duplicate ticks.
  - Show it in a supervisor tree, or explicitly `GenServer.stop` it next to `GenAgent.stop`.
- **Prose fixes.**
  - Rewrite the deferral bullet (`:43-46`): deferred ticks and prompts are bounded, `notify/2` drops on overflow with telemetry only, and `notify_ack/3` reports admission.
  - Rewrite the self-halting bullet (`:198-201`): ticks to a halted agent still run `handle_event`. With this tick clause at most one prompt is queued and it runs on `resume/1`. Stop the ticker with the agent.

**2. `guides/patterns/watcher.md`**
- **Agent state.** Add `pending: []` and `failures: []`.
- **Event handlers.** The diagnosis and welcome clauses append `{kind, details}` to `pending` before returning `{:prompt, ...}`.
- **`handle_response`.** Pop `pending` and record the action.
- **New `handle_error/3`.** Pop `pending` and append `%{event: event, reason: reason, at: ...}` to `failures`.
- **Prose fixes.** Replace the "Rate limiting" mailbox sentence with bounded-queue, `notify_ack/3` and overload text. Trim or reword the pre-v0.2 caveat. Mention `runtime_snapshot/1` for inspection.

**3. New `test/guides/heartbeat_test.exs` and `test/guides/watcher_test.exs`**
- Compile the guide modules with the same `Regex.scan` and `Code.compile_string` approach as `pool_test.exs`.
- Use a local stub backend like `PoolGuideTest.Backend`. No network or credentials.
- Heartbeat cases:
  - A failed summary turn restores the batch and records the failure, and a later tick re-summarizes it.
  - Ticks below `min_batch` after a dispatch queue nothing, including on a halted agent. Resume then drains exactly one prompt.
  - The ticker stops after `GenAgent.stop`. Check with a monitor on the ticker pid.
  - After restarting under the same name, only the new ticker ticks. Count the ticks received.
  - The ticker works under a supervisor via `child_spec`.
  - `notify_ack` returns `{:error, {:overloaded, _}}` with `max_pending_notifications: 1`.
- Watcher cases:
  - A failed diagnosis turn and a failed welcome turn are each recorded in `failures` with the originating event.
  - A successful turn still lands in `actions`.
  - An overloaded queued prompt is reported through `handle_error/3`.

I would leave the existing scenario tests, `lib/`, `mix.exs` and the other guides unchanged.

## For the caller

- Add `guides/patterns/heartbeat.md` and `watcher.md` to the `mix.exs` docs list only if they are missing. Watcher is already listed. I did not check heartbeat.
- Run `mix format --check-formatted`, `mix test test/guides`, and the project's usual lint before the PR.
REQUEST CHANGES

I checked the claims against `lib/gen_agent.ex` and `lib/gen_agent/server.ex`. I did not run the test suite because this session is read-only. `mix format --check-formatted` passes on the two new test files. No `lib/` or `test/scenarios/` files are changed, so scope is clean.

**What checks out**

- **Heartbeat failure handling** (`guides/patterns/heartbeat.md:115`, `:131-143`): a batch stays in `in_flight` until the turn ends. `handle_error/3` puts it back ahead of newer observations. This holds on every error path, because `finish_error` and `reject_generated_prompt` both call `handle_error`. Queued events are drained only after `handle_response`/`handle_error` runs (`server.ex:1793`, `:1843`), so a deferred tick sees `in_flight: nil`.
- **Watcher failure handling** (`watcher.md` `pre_turn` and `handle_error`): taking a rejected prompt from the end of the list and a starting turn from the front is correct for all three cases:
  - Halted and idle: the event was just appended to the end.
  - Rejected during the drain: `active` was already cleared by `handle_response`/`handle_error`.
  - Turn failure: `active` is set.

  A `pre_turn` skip does not call `handle_error` (`server.ex:1926`), so a direct tell that gets skipped won't record a failure with no event.
- **Halted-tick statement** (`heartbeat.md:274-278`): matches `notify_idle_prompt` (`server.ex`, halted branch). It includes the issue's correction that ticks without enough observations queue nothing.
- **Admission and overload text**: matches `notify/2`, `notify_ack/3`, `enqueue_*` and `emit_input_rejected`. The telemetry name `[:gen_agent, :input, :rejected]`, the option names, and the `{:overloaded, info}` shape are all correct. `max_pending_prompts: 0` is a valid setting (`server.ex:1466`).
- **Ticker**: `use GenServer, restart: :temporary` provides a `child_spec/1`. The monitor plus the `whereis == pid` check works, and the leftover race of one tick at most is stated honestly.

**Findings**

1. **`test/scenarios/heartbeat_scenario_test.exs:34,206` and `test/scenarios/watcher_scenario_test.exs:26`: the issue's scenario-drift item for Watcher and Heartbeat is neither fixed nor mentioned.** Both files still use different state shapes, and the heartbeat timer test still writes its own `Task.async` loop instead of using `Heartbeat.Ticker`. This part does not overlap #236. Only the Supervisor scenario belongs to #236. The report says "Supervisor cleanup acceptance remains scoped to #236" and says nothing about these two files. Do one of these:
   - align the files with the guides,
   - remove them as superseded by `test/guides/*`,
   - or state in the report that the guide tests replace them and the files stay on purpose.
2. **`guides/patterns/heartbeat.md:278`: "Stop the ticker explicitly with `GenServer.stop/1` when halting" can't be done from the agent.** In this variation the agent halts itself inside `handle_event`, and it has no ticker pid. Either say that the owner of the ticker stops it (for example, after a `[:gen_agent, ..., :halted]` telemetry event or a status check), or show the agent being given the ticker pid.
3. **`guides/patterns/heartbeat.md:150`, `:212-216`: the guide says the ticker is supervised but does not explain what happens when the agent restarts.** The ticker is `:temporary`. If the agent's supervisor restarts it, the heartbeat stops silently and nothing starts a new ticker. Under `rest_for_one` a temporary child would not restart either. The moduledoc says to start a new ticker for a replacement agent. Add one sentence to "Using it" that says the same, so nobody assumes the supervisor brings it back.
4. **`guides/patterns/heartbeat.md:141` (minor):** if the backend keeps failing, `observations` and `failures` grow without limit. Eventually the prompt hits the prompt byte cap and gets rejected as overloaded on every tick. The guide notes the data is in memory only, but it doesn't mention this growth. One sentence would be enough, or a cap on `failures`.
5. **`guides/patterns/watcher.md:182`, `heartbeat.md:245` (minor):** "`interrupt_request/3` targets one such request" leaves out that it only works on the active turn. A queued request returns `{:error, :not_current}`, and `cancel_request/3` handles the queued case (`gen_agent.ex:800-812`).
6. **`test/guides/heartbeat_test.exs:161` (minor flake risk):** `which_children == []` is checked as soon as the test gets the ticker's `:DOWN`. The supervisor processes the ticker's `EXIT` separately, and nothing orders that `EXIT` before the test's `which_children` call. Wrap the check in the existing `await/1` helper.
7. **Tests (note, not a blocker):** the branch that sees `whereis != pid` before `:DOWN` arrives has no test. The replacement test passes because the old ticker is already dead. That is acceptable given the race, but the report's claim that the ticker "cannot send ticks to a replacement" is backed only by the monitor path.
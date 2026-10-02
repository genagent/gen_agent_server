REQUEST CHANGES

The 9 new tests pass locally (`mix test test/guides/heartbeat_test.exs test/guides/watcher_test.exs`). One factual claim in the guide is wrong, though: the prose says the ticker does one thing and the code does another.

**Blocking**

1. `guides/patterns/heartbeat.md:58-62`: The prose says that "to avoid a name-reuse race, this ticker sends the same `{:notify, event}` cast directly to its monitored PID" and that it "deliberately uses the runtime's notification message protocol". The code doesn't do that. `Heartbeat.Ticker.handle_info(:tick, ...)` (around line 180) checks `GenAgent.whereis(state.agent) == state.pid` and then calls `GenAgent.notify(state.agent, :tick)`. That goes through the registered name (`lib/gen_agent.ex:760-762`, which uses `via(name)`), not the PID.
   - So a small race remains. If the agent dies and a replacement registers under the same name between the `whereis` check and the cast, the replacement gets one tick.
   - Pick one fix:
     - **Reword the prose (preferred):** say the ticker checks before each pulse that the name still resolves to its monitored PID, and stops on `:DOWN` or a mismatch. This keeps the guide on the public `notify/2` API instead of the internal `{:notify, _}` message shape.
     - **Change the code:** cast directly to `state.pid`, which matches the prose but ties the guide to internals.
   - The test at `test/guides/heartbeat_test.exs:148` checks the stop-on-`:DOWN` behaviour and passes either way, so it neither confirms nor contradicts the prose.

**Non-blocking**

2. `guides/patterns/watcher.md`, the `pre_turn/2` clause (about line 117): it only matches `pending: [event | rest]`.
   - Any turn that doesn't come from an event (`tell`/`ask`) raises `FunctionClauseError`. The server catches it and skips the turn with a logged warning (`lib/gen_agent/server.ex:1578-1596`), but the caller gets `:pre_turn_skipped` with no explanation. The guide does say "drive this agent only through events".
   - A fallback `def pre_turn(prompt, state), do: {:ok, prompt, state}` would make that constraint harmless instead of a crash path.
3. `test/guides/heartbeat_test.exs:170-176`: `:telemetry.attach` gets an anonymous function, which logs a "local function" info message on every run. Other guide tests don't produce this. Using a named module function (or `&__MODULE__.handler/4`) would keep the output clean.

**Claims checked against the code (all hold)**

- **Bounded admission and overload:**
  - `notify/2` always returns `:ok` (`lib/gen_agent.ex:747-762`).
  - `notify_ack/3` covers admission only (`:764-781`).
  - Deferred event prompts that can't be queued go to `handle_error/3` (`server.ex:1717-1740`).
  - The guides' wording on these matches the code.
- **Deferred events are handled after the turn's decision:** `drain_pending_events` runs after `handle_response`/`handle_error` returns (`server.ex:1793`, `1843`). So Watcher's `active` is already `nil` when a deferred prompt is rejected, and the "pop from tail" logic in its `handle_error` is correct.
- **Dispatch failures:** when dispatch fails after `pre_turn` (`reject_dispatch`, `server.ex:1201`), `active` is set and the failure is recorded against the right event.
- **Heartbeat:**
  - The `in_flight` guard plus restoring the failed batch in `handle_error` keeps the work and allows at most one queued batch while halted.
  - The corrected Self-halting wording matches the issue's note that ticks without enough new observations queue nothing, and the halted-ticks test covers it.
- **Ticker lifecycle:** it is now a supervisable `GenServer` (`restart: :temporary`) that stops on `:DOWN`. The test covers no orphaned ticker after `stop`, removal from the supervisor's children, and a single tick reaching the replacement.
- **APIs:** `runtime_snapshot/2`, `tell_with_completion/4` and `interrupt_request/3` exist with the arities and meanings the guides give them.
- **Scope:** only the two guides and two new tests changed. This matches sibling PRs #346/#347 (one guide plus one test each, no CHANGELOG). Core runtime and the Supervisor scenario are untouched.
- **Overlap with #236:** the issue's acceptance item for the Supervisor scenario (wrong protocol, leaked workers) is not addressed here. That matches the instruction, but the PR should say #244's acceptance is only partly met until #236 lands. The report says this, and the PR body should too.
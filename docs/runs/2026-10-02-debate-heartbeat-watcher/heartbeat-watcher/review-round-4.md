REQUEST CHANGES

I checked the change against `lib/gen_agent.ex` and `lib/gen_agent/server.ex` and confirmed most of its claims. Two problems need fixing first: a code comment in the Watcher guide is wrong, and both guides point readers at APIs that the agents they describe can't use. Plan mode was active, so I did not run the tests. The "53 passing" figure comes from the implementer's report and I haven't confirmed it.

**Blocking**

1. **`guides/patterns/watcher.md:117-123`**: the comment says a direct tell/ask "is skipped explicitly". That only holds when `pending` is empty. The first `pre_turn/2` clause matches any prompt, so a `tell` that arrives while an event is queued (for example, while halted) does the following:
   - It takes the head event as `active`.
   - It runs, and its response is recorded as that event's action.
   - The event's own prompt later reaches `pre_turn` with `pending == []` and is skipped.

   The skip path (`server.ex:1115-1120`) calls only `record_error`, not `handle_error/3`. So the event is dropped with no failure record, which is the loss this issue is meant to fix. The fix: store `{event, prompt}` in `pending` and match the incoming prompt against the head before claiming it. Skip anything that doesn't match. Add a test where a tell arrives while an event prompt is queued.

2. **`guides/patterns/watcher.md:180-184` and `guides/patterns/heartbeat.md:245-251`**: both guides tell readers to use `tell_with_completion/4` and `cancel_request/3`, right after saying the agent must only be driven by events.
   - In Watcher, `pre_turn` skips or misattributes every direct tell (see item 1).
   - In Heartbeat, a tell that succeeds goes through `handle_response`, which clears `in_flight` and records the tell's reply as a summary. That loses a batch that is queued while halted.
   - `cancel_request/3` only acts on queued tells; it returns `:not_found` for event refs (`gen_agent.ex:830-832`). So "handles a queued request" doesn't apply to anything these agents enqueue.

   Either say these APIs belong on a separate agent, or remove the sentences. Keeping `runtime_snapshot/2` and `interrupt_request/3` is fine; the ref for the latter is available from `runtime_snapshot(...).current_request.ref`.

**Non-blocking**

3. **`guides/patterns/heartbeat.md:60` and `:223-228`**: the guide calls dropped pulses harmless, but the usage snippet still sends observations with `notify/2`. Observations are the data that matters, and that call silently drops them on overflow. Say so, or use `notify_ack/3` for observations.
4. **`guides/patterns/watcher.md:43-46`**: the advice to "let the source retry rejected events" is incomplete. While halted, `notify_ack` returns `{:error, {:overloaded, _}}` even though `handle_event` already ran and `handle_error/3` has already recorded the event in `failures` (`server.ex:1057-1064`). A source that retries will create a duplicate record. Say which rejection this is.
5. **`guides/patterns/heartbeat.md:196`**: `terminate/2` only cancels a timer. It doesn't run on supervisor shutdown unless the process traps exits, and when it does run, the process is exiting anyway. It can be removed, or it needs a comment explaining why it's there.
6. **Test naming in `test/guides/heartbeat_test.exs`**: the test "...cannot tick a replacement" shows that the old ticker is dead and that a new ticker sends one tick. The guide itself (`heartbeat.md:58-60`) admits a race where a replacement can receive one tick. "does not survive its agent" would be more accurate.
7. **`halt/1` in both test files**: it reaches into the internal `{:idle, %Data{halted: true}}` shape. It's commented as test-only, but it will break silently if the server's data shape changes. Acceptable, but worth noting.

**Verified as correct**
- `notify/2` always returns `:ok`, and overflow emits `[:gen_agent, :input, :rejected]` telemetry (`server.ex:936,964`).
- `notify_ack/3` behaves as the guides describe (`gen_agent.ex:764-781`).
- A deferred event's generated prompt that is rejected goes to `handle_error/3` (`server.ex:1727-1749`).
- Halted agents still run `handle_event/2` and queue generated prompts (`server.ex:1057`).
- A limit of `0` is valid (`server.ex:1466`).
- Watcher's "remove from the tail on rejection" is correct: rejections only happen with `active == nil`, right after `handle_event` appends.
- Heartbeat's single-`in_flight` guard keeps generated prompts to at most one, so `handle_error/3` can't attribute a failure to the wrong batch.
- The issue's correction holds: ticks without enough new observations queue no prompt, and a test covers it.
- `use GenServer, restart: :temporary` gives `Heartbeat.Ticker` a `child_spec/1`. The monitor plus the `whereis == pid` check stops it ticking after its agent stops, and a test covers that.

**Scope**
- No core runtime, Supervisor scenario, or unrelated guide files changed, and #236 is not claimed.
- The issue's Supervisor acceptance item (scenario drift and worker cleanup) is still unaddressed, as the instructions required. The PR should say #244's acceptance is not fully met until #236 lands.

I added the opt-in `stream_to: pid` option to `tell_with_completion/5`. Nothing has been compiled, formatted or tested. The shell here refused `mix`, so the caller needs to run `mix format`, `mix test` and clippy-equivalent checks. Nothing was committed or branched.

Files changed:

- `lib/gen_agent.ex`
  - `tell_with_completion/5` accepts `stream_to:` and raises `ArgumentError` unless it is `nil` or a pid.
  - The call message gains a 5-tuple form only when `stream_to` is set, so calls without it send the same message as before.
  - The function docs describe the `{:gen_agent, :event, name, ref, %GenAgent.Event{}}` message. They cover same-pid ordering against completion, retention behavior, no backpressure, dead recipients, interrupt/watchdog drops, and the cases that stream nothing.
  - The moduledoc API list mentions `stream_to:`.
- `lib/gen_agent/server.ex`
  - A new `stream_recipients` map on `Data` holds recipients by ref. It is redacted in `format_status`.
  - Three new `:tell_with_completion` clauses handle the 5-tuple: halted with `on_halt: :fail` rejects, idle dispatches, and busy queues. A recipient is registered only after admission succeeds.
  - `try_dispatch` pops the recipient first, so pre-turn skip, halt, invalid, and dispatch failure all clean up. The popped recipient goes into the current request, and a relay flag goes to the task.
  - Queued cancellation deletes the entry. A halt-failed queued request is never dispatched, so its entry stays in the map; the test for that path asserts the map ends empty, so it is the one most likely to fail.
  - `maybe_handle_stream_event` now takes `{module, relay}`. It runs the existing callback, then sends `{:gen_agent_stream, ref, event}` to the agent for opted-in requests only.
  - The agent forwards that message only while the active request's ref matches. Stale messages fall through to the existing catch-all and are dropped.
  - Compact mode forwards events that retained history omits. Lossless mode does not forward the event it rejects for overflow.
- `test/gen_agent/stream_to_test.exs` (new): 17 tests using a gated lazy-stream backend and mailbox ordering, with no sleeps. They cover:
  - ordering and ref tagging, and callback-before-relay
  - default off, option validation, and a separate recipient
  - FIFO across queued requests, and queued cancellation
  - pre-turn skip and halt, halted rejection, halt failing a queued request, and overload
  - backend error, interrupt and watchdog, and stale-ref fencing (including a late event for a finished ref)
  - a dead recipient, and both retention modes

I put the tests in a new file rather than extending `request_completion_test.exs`, because they need their own streaming backend. Ensemble forwarding and per-event telemetry are left out.
# Issue #106: request-ref-correlated stream delivery (core first slice)

Verified against local `main` at `8f6cb9d` (branch `feat/core-stream-recipient-106`, clean).

## Context

Callers of `tell_with_completion` get one terminal message but no deltas. Applications that render streaming text must add forwarding inside each agent module's `handle_stream_event/2`, and cannot correlate a delta with a queued request ref. Goal: an opt-in, per-request stream recipient on `tell_with_completion`, with ordering stronger than "probably before completion".

## What the issue gets wrong on current main

- The ref is already in scope inside the task. `dispatch/5` passes `{owner, request_ref}` to `run_prompt/7` (`lib/gen_agent/server.ex:1094-1103`, `1156-1164`); it is used for the checkpoint call (`server.ex:1167-1169`). It just is not threaded into `consume_stream/8` (`server.ex:1180-1189`) or `maybe_handle_stream_event/3` (`server.ex:1403-1409`).
- Still true: `handle_stream_event/2` has no ref (`lib/gen_agent.ex:296`); `pre_turn/2` likewise (`gen_agent.ex:347`); `emit_prompt_start` runs after the task is spawned (`server.ex:1109-1111`); completion is a single message (`server.ex:1802-1845`); no per-event telemetry exists (only `[:gen_agent, :event, :received]` for `notify/2`, `server.ex:1973`).

## Choice: `stream_to:` option on `tell_with_completion/5`

Recommended over the alternatives because:

- **It solves the stated scenario without touching agent modules.** A LiveView passes `stream_to: self()` and matches on the ref it already holds. `handle_stream_event/3` would still require every module to forward, and changes the behaviour contract (`gen_agent.ex:410`, `434`, `453` list arity 2 in optional callbacks, defaults, and overridables).
- **The option surface already exists.** `tell_with_completion/5` takes a keyword list and validates `:on_halt` (`gen_agent.ex:679-690`). One more key is additive; the 2-4 arity forms are unchanged.
- **Telemetry is the wrong transport for a per-request consumer.** Handlers run synchronously in the emitting process (the prompt task), are global (every handler sees every agent's deltas), and have no recipient. It belongs in the observability follow-up, not the first slice.

## Message shape

`{:gen_agent, :stream, name, ref, %GenAgent.Event{}}`

Use the `:stream` tag, not `:event`, to avoid confusion with `notify/2` events and `[:gen_agent, :event, :received]`. It sits next to the existing `{:gen_agent, :completion, name, ref, outcome}` (`gen_agent.ex:638-639`).

## Delivery path: relay through the agent, not a direct send from the task

The task sends `{:"$gen_agent_stream", request_ref, event}` to `owner`. The agent forwards that to the recipient only while `current_request.request_ref == request_ref`.

Why relay instead of sending straight from the task:

- **Completion ordering is guaranteed, not just likely.** BEAM orders messages only per sender/receiver pair. With a relay, task-to-agent FIFO puts every relay message ahead of the `Task.async` reply `{task_ref, result}`, which is handled at `server.ex:682-697`. Agent-to-recipient FIFO then delivers every forwarded delta ahead of the completion sent from `record_success/3` or `record_error/3` (`server.ex:1802-1845`). A direct send from the task gives two senders and no ordering guarantee.
- **No deltas after completion on interrupt or watchdog.** Those paths clear `current_request` (`server.ex:1709`, `1760`). Any relay message still in the agent mailbox no longer matches and falls into the existing catch-all `dispatch_event(:info, _msg, _state, _data)` (`server.ex:731`). The next turn has a different ref, so the guard also covers that case.
- Cost: one extra agent message per event, and only for requests that opted in. The task sends nothing when `stream_to` is nil.

## Implementation (core)

1. **API** (`lib/gen_agent.ex:679-690`): read `stream_to = Keyword.get(opts, :stream_to)` and validate that it is `nil` or a pid (raise `ArgumentError`, same as `:on_halt`). Call `{:tell_with_completion, prompt, recipient, on_halt, stream_to}`. When `stream_to` is nil, keep sending the existing 4-tuple so the current server clauses and Ensemble's call (`extensions/ensemble/lib/gen_agent_ensemble/server.ex:684`) are untouched.
2. **State**: add a Data field `stream_recipients: %{}` (ref => pid). It is a side map so the request `kind` tuples stay unchanged. Those tuples are matched in about 12 places: `server.ex:780-832`, `1598`, `1802-1845`, and `request_origin/1` telemetry. Add `stream_recipients: :redacted` to format_status (`server.ex:220-229`).
3. **Admission** (`server.ex:428-455`): add 5-tuple clauses that put `ref => stream_to` before `try_dispatch` on the idle path and after `enqueue_prompt` succeeds on the queued path. `queue_tell/5` (`server.ex:834-851`) needs to return the ref, or take a callback. A simpler alternative is to generate the ref in the caller clause. On overload, register nothing.
4. **Dispatch** (`try_dispatch/4`, `server.ex:1037`): `Map.pop` the recipient at entry. This covers every exit: normal dispatch, pre_turn skip, halt, invalid return, and `reject_dispatch`. Pass it to `dispatch/5` and store it as `current.stream_to` (`server.ex:1113-1122`). Pass a boolean `relay?` into `run_prompt`, then `consume_stream`, then `capture_event`/`capture_compact_event`. Send the relay message after `maybe_handle_stream_event` so the callback sees the event first. Relay accepted events only, matching what `handle_stream_event` sees. The lossless overflow event is not relayed (`server.ex:1342-1349`).
5. **Relay clause** placed before `server.ex:731`: `dispatch_event(:info, {:"$gen_agent_stream", ref, event}, :processing, %Data{current_request: %{request_ref: ref, stream_to: pid}})` sends to `pid` and returns `:keep_state_and_data`. Stale messages fall through to the catch-all.
6. **Cleanup**: `Map.delete` in `finish_queued_tell_cancel/5` (`server.ex:792`) and in `fail_halt_aware_queued/1` (`server.ex:1593`).
7. **Docs**: add a stream paragraph to the `tell_with_completion` doc (`gen_agent.ex:633-670`) and the moduledoc API list (`gen_agent.ex:160`). Add a CHANGELOG entry via the conventional commit `feat(core): ...`.

## Semantics to document

- **Queued requests**: no stream messages until dispatch. A cancelled, pre_turn-rejected, or halt-failed request gets zero stream messages and its one completion.
- **Early deltas**: like completion today (`gen_agent.ex:640-643`), stream messages can arrive before `{:ok, ref}` is returned. They stay in the mailbox; callers match on the ref after the call returns. No delta is lost when the task emits before `dispatch/5` sets `current_request`: the relay message waits in the agent mailbox until the call handler finishes.
- **Ordering**: events for one ref arrive in stream order, and all of them arrive before that ref's completion message.
- **Cancellation, interrupt, watchdog**: no stream message after the completion. Deltas already delivered are not retracted. The `Response` in `{:ok, response}` is authoritative.
- **Callback compatibility**: `handle_stream_event/2` still runs first, unchanged, in the task. Agents that already forward continue to work.
- **Recipient death**: sends to a dead pid are dropped. The agent does not monitor `stream_to` and the turn continues, matching completion recipients (`gen_agent.ex:656-657`, test at `request_completion_test.exs:239`). `stream_to` may differ from `recipient`.
- **Agent death**: no further stream or completion messages. Monitor the agent, as documented today.
- **Backpressure**: none. The relay sends asynchronously, so a slow recipient grows its own mailbox and does not block the turn. Document this.

## Tests

Add them to `test/gen_agent/request_completion_test.exs`, reusing its gated `Backend` (`:6-30`, `:release` receive). Add a variant that returns a lazy `Stream.resource` and blocks on a message between events.

1. Opt-in: deltas arrive with the matching ref and in order, then exactly one completion. `refute_receive` stream messages afterwards.
2. Early delta: the task emits the first delta, then blocks. `assert_receive` the stream message before `send(task, :release)`, and `refute_receive` completion at that point.
3. Queued: hold the first request. The second request (with `stream_to`) gets no stream messages until it dispatches, and every message carries the second ref.
4. Cancel queued: zero stream messages, one `{:error, :cancelled}`. pre_turn skip, halt, and `on_halt: :fail` behave the same way.
5. Interrupt mid-stream: after the `{:error, _}` completion, `refute_receive {:gen_agent, :stream, _, ^ref, _}`.
6. Default off: no stream messages without the option. `handle_stream_event/2` still sees every event (cross-check with `stream_state_test.exs`).
7. `stream_to` dies mid-turn: the agent stays alive and `recipient` still gets the completion.
8. Both retention modes (`:compact`, `:lossless`) relay. In lossless mode, the overflow event is not relayed.
9. `ArgumentError` on a non-pid `stream_to`.

Use `assert_receive` with refs only, and no sleeps. Ordering assertions should read the mailbox with sequential `receive` blocks.

## Ensemble follow-up (separate PR)

- `GenAgentEnsemble.tell_with_completion/4` (`extensions/ensemble/lib/gen_agent_ensemble.ex:58`) takes `stream_to`. The ensemble server passes `stream_to:` to sub-agent calls (`server.ex:684`) and wraps the deltas with the ensemble token so consumers see `{:gen_agent_ensemble, :stream, ensemble, token, member, event}`. Design this after core ships, given the cancellation and token semantics added in #339.

## Later core follow-ups (not this slice)

- `[:gen_agent, :stream, :event]` telemetry with `agent` and `ref`, likely sampled or opt-in.
- Emit `[:gen_agent, :prompt, :start]` before spawning the task (`server.ex:1094-1111`).
- An optional `handle_stream_event/3` with the ref, if callback-side correlation is still wanted.

## Verification

`mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix test` (focused on `test/gen_agent/request_completion_test.exs`), and the Ensemble test suite unchanged and passing.

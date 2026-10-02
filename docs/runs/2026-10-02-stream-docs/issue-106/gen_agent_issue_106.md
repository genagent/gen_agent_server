Found in a read-only review of `main` at `b8f8ab4`. Code links point at that commit; `main` has moved since (core 0.4.0).

## Problem

`c:handle_stream_event/2` ([`lib/gen_agent.ex:277`](https://github.com/genagent/gen_agent/blob/b8f8ab4/lib/gen_agent.ex#L277)) and `c:pre_turn/2` ([`lib/gen_agent.ex:328`](https://github.com/genagent/gen_agent/blob/b8f8ab4/lib/gen_agent.ex#L328)) do not receive the request ref, and `run_prompt/7` ([`lib/gen_agent/server.ex:785-795`](https://github.com/genagent/gen_agent/blob/b8f8ab4/lib/gen_agent/server.ex#L785-L795), 811-838) runs the prompt task without it, so callback code has no in-band way to tag a stream event with the ref returned by `tell/3` or `tell_with_completion/4`. `tell_with_completion/4` sends one terminal message (server.ex:1267-1271, 1286-1290) and no telemetry event is emitted per stream event (server.ex:1332-1394). An application that renders deltas must add forwarding to each agent module, as gen_agent_live/lib/gen_agent_live/chat_agent.ex:68-93 and fio/lib/fio/capo.ex:68-77 do. Correlation is possible only indirectly: turns are serialized, and `[:gen_agent, :prompt, :start]` carries the ref, but that event is emitted after the task is spawned (server.ex:784-797), so its ordering relative to the first delta is not guaranteed. Fix options: an opt-in `stream_to` recipient on `tell_with_completion` producing `{:gen_agent, :event, name, ref, event}`, an optional `handle_stream_event/3` with the ref, or a `[:gen_agent, :stream, :event]` telemetry event carrying `agent` and `ref` in line with the README's telemetry-first principle ([`README.md:191-195`](https://github.com/genagent/gen_agent/blob/b8f8ab4/README.md#L191-L195)).

**Evidence.** [`lib/gen_agent.ex:277`](https://github.com/genagent/gen_agent/blob/b8f8ab4/lib/gen_agent.ex#L277) `@callback handle_stream_event(Event.t(), agent_state()) :: agent_state()`; [`lib/gen_agent.ex:328`](https://github.com/genagent/gen_agent/blob/b8f8ab4/lib/gen_agent.ex#L328) `@callback pre_turn(prompt :: String.t(), agent_state()) :: pre_turn_return()`. [`lib/gen_agent/server.ex:935-941`](https://github.com/genagent/gen_agent/blob/b8f8ab4/lib/gen_agent/server.ex#L935-L941) invokes `module.handle_stream_event(event, state)` inside the prompt task with no ref in scope (the ref is not passed to `run_prompt/7`, [`lib/gen_agent/server.ex:784-795`](https://github.com/genagent/gen_agent/blob/b8f8ab4/lib/gen_agent/server.ex#L784-L795)). The ref is available only in `[:gen_agent, :prompt, :start]` telemetry and in `handle_response/3` after the turn. [`lib/gen_agent/server.ex:1267-1271`](https://github.com/genagent/gen_agent/blob/b8f8ab4/lib/gen_agent/server.ex#L1267-L1271) sends a single completion message per request. No guide under guides/patterns uses `handle_stream_event`.

**Scenario.** A LiveView chat sends `tell_with_completion` and wants to render text deltas for that message. The agent module must be written to broadcast from `handle_stream_event/2` to a topic stored in its state, and the LiveView cannot tell which request a delta belongs to when prompts are queued.

## Proposed fix

- Add an opt-in stream recipient to `tell_with_completion` (for example `stream_to: pid` producing `{:gen_agent, :event, name, ref, event}` messages sent from the prompt task), or add an optional `handle_stream_event/3` that receives the request ref.

## Acceptance

- The new behaviour is covered by tests and documented in the relevant moduledoc.

## Verification

- Confirmed by an independent code trace.
- Reported independently by 2 other review passes.

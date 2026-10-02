I’ll keep this review read-only and use the current source as the authority.


The issue still needs a core fix. Reviewed local HEAD **`8f6cb9d`**, version **0.6.2**, rather than the original `b8f8ab4`. No files changed; no tests run.

Claims that still hold:

- Neither callback receives the request ref: [`handle_stream_event/2`, lib/gen_agent.ex:296](/private/tmp/gen_agent_issue_106/lib/gen_agent.ex:296) and [`pre_turn/2`, :347](/private/tmp/gen_agent_issue_106/lib/gen_agent.ex:347).
- Stream consumption still invokes `module.handle_stream_event(event, state)` without correlation metadata: [lib/gen_agent/server.ex:1403](/private/tmp/gen_agent_issue_106/lib/gen_agent/server.ex:1403).
- Completion delivery provides terminal outcomes, without a stream subscription: [server.ex:1802](/private/tmp/gen_agent_issue_106/lib/gen_agent/server.ex:1802) and [server.ex:1833](/private/tmp/gen_agent_issue_106/lib/gen_agent/server.ex:1833). `/5` currently reads only `on_halt`; a supplied `stream_to` is silently ignored: [gen_agent.ex:681](/private/tmp/gen_agent_issue_106/lib/gen_agent.ex:681).
- Prompt-start telemetry still runs after task creation, so it cannot reliably establish correlation before the first callback: [server.ex:1094](/private/tmp/gen_agent_issue_106/lib/gen_agent/server.ex:1094), [server.ex:1113](/private/tmp/gen_agent_issue_106/lib/gen_agent/server.ex:1113).
- There is no per-stream-event telemetry. `:event, :received` describes application notifications: [server.ex:1972](/private/tmp/gen_agent_issue_106/lib/gen_agent/server.ex:1972). The telemetry-first principle remains at [README.md:204](/private/tmp/gen_agent_issue_106/README.md:204).
- No guide under `guides/patterns` mentions `handle_stream_event`. The cited external application examples were not reverified.

Already resolved or outdated:

- **The prompt task now has the ref.** `dispatch` passes `{owner, request_ref}` into `run_prompt/7`, which uses it for session checkpoints: [server.ex:1102](/private/tmp/gen_agent_issue_106/lib/gen_agent/server.ex:1102), [server.ex:1164](/private/tmp/gen_agent_issue_106/lib/gen_agent/server.ex:1164). It remains absent from `consume_stream`.
- The ref is no longer available *only* through prompt-start telemetry and `handle_response`: turn telemetry also includes it, and error/post-turn callbacks receive it: [server.ex:1922](/private/tmp/gen_agent_issue_106/lib/gen_agent/server.ex:1922), [server.ex:1735](/private/tmp/gen_agent_issue_106/lib/gen_agent/server.ex:1735).
- The options-bearing `/5` API already exists; adding another public arity is unnecessary: [gen_agent.ex:679](/private/tmp/gen_agent_issue_106/lib/gen_agent.ex:679).

Smallest concrete patch: **three files**.

1. **[lib/gen_agent.ex](/private/tmp/gen_agent_issue_106/lib/gen_agent.ex:633)** — Validate `stream_to` as `nil` or a pid in `/5`; preserve existing calls when omitted. Document `{:gen_agent, :event, name, ref, %GenAgent.Event{}}` in the function docs and moduledoc API list. Cover early delivery, optional separate recipients, no backpressure, dead recipients, and retention semantics. Keep callbacks unchanged.

2. **[lib/gen_agent/server.ex](/private/tmp/gen_agent_issue_106/lib/gen_agent/server.ex:428)** — Add opt-in admission handling, including halted rejection. Store queued recipients by ref in a separate map, preserving existing request-kind tuples. Extend `queue_tell` with an optional recipient argument and register it only after successful admission. Pop the entry at `try_dispatch`, carrying it into the current request and a relay context into stream consumption. Relay after the existing callback, only for opted-in requests. Forward only events matching the active request; discard stale messages. Remove queued entries on cancellation and halt failure, and redact the map in status formatting.

   Match existing capture behavior: compact mode forwards even events omitted from retained history ([server.ex:1297](/private/tmp/gen_agent_issue_106/lib/gen_agent/server.ex:1297)); lossless mode excludes the event rejected for overflow ([server.ex:1340](/private/tmp/gen_agent_issue_106/lib/gen_agent/server.ex:1340)). Popping before dispatch also handles pre-turn rejection and unavailable task supervisors without leaking recipients.

3. **[test/gen_agent/request_completion_test.exs](/private/tmp/gen_agent_issue_106/test/gen_agent/request_completion_test.exs:6)** — Extend the gated backend with a lazy stream and explicit release/ack messages. Cover option validation, default-off compatibility, callback behavior, early events, FIFO correlation, queued cancellation, pre-turn outcomes, overload/halted admission, dispatch failure, backend failure, watchdog/interrupt, stale events after completion and during the next request, both retention modes, dead/separate recipients, and recipient-state cleanup. Use mailbox barriers and ordered receives rather than sleeps or selective receives that could hide reordering.

Two corrections to the supplied design matter: relay ordering guarantees that forwarded events precede completion **when both target the same pid**; separate processes have no shared arrival order. On interrupt/watchdog, pending events may be discarded—the guarantee is no later forwarding for the completed ref, not delivery of every generated event.

Keep Ensemble forwarding and per-event telemetry outside this patch.
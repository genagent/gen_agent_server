I’ll keep this read-only and check the current source and design candidate for the remaining stream-forwarding gap.


Current checkout is `df6d873` (#341). **Completion, cancellation, and polling-based await are already resolved; Ensemble stream forwarding remains missing.** No files changed or checks run.

Already resolved:

- `tell_with_completion/4`, `await/3`, and `cancel/2` exist in [gen_agent_ensemble.ex:61](/private/tmp/gen_agent_issue_259_stream/extensions/ensemble/lib/gen_agent_ensemble.ex:61), lines 80 and 97 respectively.
- Await registers waiters instead of polling ([server.ex:253](/private/tmp/gen_agent_issue_259_stream/extensions/ensemble/lib/gen_agent_ensemble/server.ex:253)); the IEx helper delegates to it ([iex.ex:122](/private/tmp/gen_agent_issue_259_stream/extensions/ensemble/lib/gen_agent_ensemble/iex.ex:122)).
- Completion and cancellation already have tests, including a completion queued behind cancellation ([completion_test.exs:67](/private/tmp/gen_agent_issue_259_stream/extensions/ensemble/test/gen_agent_ensemble/completion_test.exs:67), [cancel_test.exs:202](/private/tmp/gen_agent_issue_259_stream/extensions/ensemble/test/gen_agent_ensemble/cancel_test.exs:202)).
- Core accepts `stream_to:` and relays ref-tagged events ([gen_agent.ex:700](/private/tmp/gen_agent_issue_259_stream/lib/gen_agent.ex:700), [core server.ex:775](/private/tmp/gen_agent_issue_259_stream/lib/gen_agent/server.ex:775)).

Still holds:

- Ensemble passes completion options directly to strategies without reserving `stream_to:` ([server.ex:55](/private/tmp/gen_agent_issue_259_stream/extensions/ensemble/lib/gen_agent_ensemble/server.ex:55), line 236).
- Child dispatch supplies only `on_halt: :fail`; no stream-event handler exists, so incoming events hit the catch-all ([server.ex:681](/private/tmp/gen_agent_issue_259_stream/extensions/ensemble/lib/gen_agent_ensemble/server.ex:681), [server.ex:459](/private/tmp/gen_agent_issue_259_stream/extensions/ensemble/lib/gen_agent_ensemble/server.ex:459)).
- Cancellation’s selective drain matches only completions. Adding forwarding without fixing this would allow earlier events to be skipped ([server.ex:722](/private/tmp/gen_agent_issue_259_stream/extensions/ensemble/lib/gen_agent_ensemble/server.ex:722)).
- Strategy callbacks still omit streaming ([strategy.ex:99](/private/tmp/gen_agent_issue_259_stream/extensions/ensemble/lib/gen_agent_ensemble/strategy.ex:99)); this scoped fix needs no new callback.
- The Hex constraint still permits core 0.6.x ([mix.exs:46](/private/tmp/gen_agent_issue_259_stream/extensions/ensemble/mix.exs:46)). Ensemble has no stream-forwarding tests.

The design candidate is largely applicable, with two corrections. Early task stream messages are possible; mapping is safe because Ensemble finishes the blocking dispatch call and registers the returned ref before processing its mailbox ([server.ex:692](/private/tmp/gen_agent_issue_259_stream/extensions/ensemble/lib/gen_agent_ensemble/server.ex:692)). Also, injecting events and completion **before** calling cancel does not reliably exercise the selective drain: queue cancel first while Ensemble is suspended, then events/completion, then resume.

Smallest concrete change:

1. **`extensions/ensemble/lib/gen_agent_ensemble/server.ex`** — Pop and validate `stream_to: pid | nil` before strategy callbacks. Register a token recipient before dispatch; pass `stream_to: self()` only for opted-in tokens. Reuse `in_flight` and `dispatch_contexts` to send:
   ```elixir
   {:gen_agent_ensemble, :event, session, token,
    %{agent: bare_member, dispatch: ordinal, event: normalized_event}}
   ```
   Require both an active child ref and token recipient. Remove the recipient in `finish_token/3` before completion delivery; existing ref removal fences completed, cancelled, and down children. Initialize and redact the new map. Extend both cancellation drain call sites to consume child events and completions in arrival order.

2. **`extensions/ensemble/lib/gen_agent_ensemble.ex`** — Document opt-in behavior, payload, zero-based per-token ordinals, same-PID event-before-completion ordering, terminal fencing, and best-effort delivery.

3. **New Ensemble streaming test/support files; existing `cancel_test.exs` and `format_status_test.exs`** — Use gated streams and explicit barriers, without sleeps. Cover Solo ordering, multiple members, repeated dispatch to the same member, default-off/mixed tokens, option stripping/validation, separate recipients, cancellation drain races, and late-event fencing/cleanup after success, error, cancellation, rejection, agent down, and session halt. Include early token completion while peers remain active and state redaction.

4. **`extensions/ensemble/mix.exs`** — Require `{:gen_agent, "~> 0.7.0"}` for Hex; retain the local path dependency. Hex-resolution CI must wait for core 0.7.0 publication.

No core source or strategy behavior changes are needed. Package checks and PR work remain with the caller.
# Ensemble token-correlated stream forwarding (#259 slice 3)

## Context

Ensemble 0.6.0 shipped `tell_with_completion/4`, `await/3`, and `cancel/2`. Core #341 (df6d873) added
`GenAgent.tell_with_completion/5` with `stream_to: pid`, which sends
`{:gen_agent, :event, name, ref, %GenAgent.Event{}}` for the active turn only, in stream order, and
before the completion message when `stream_to` and `recipient` are the same process. The remaining
slice: expose sub-agent stream events to an opted-in caller, keyed by the Ensemble token rather than
child refs. Scope stays in `extensions/ensemble`. No core change is needed (gap analysis below). One
packaging step is required: the Hex dependency constraint.

## Verified facts against current source

- `Server.dispatch/4` (server.ex:681) already calls core `tell_with_completion/5` with
  `self()` as recipient and `on_halt: :fail`, then registers `in_flight[ref] = {agent, token}` and
  `dispatch_contexts[ref] = {started_at, ordinal}` (server.ex:692-703). That gives the complete
  child ref -> {member, token, per-token ordinal} mapping. No new correlation table is needed.
- `handle_info_impl/2` has no clause for `{:gen_agent, :event, ...}`. The catch-all (server.ex:459)
  would drop it.
- Every terminal path for a token goes through `reply_to_token/3` -> `finish_token/3`
  (server.ex:798, 908): strategy reply/reply_error, `finish_cancellation`, `reject_dispatch`, and
  `{:halt_session, _}`.
- `drain_completions/1` (server.ex:722) selectively receives only completion messages. Once events
  exist, that would reorder: a completion could be handled ahead of its earlier events, and those
  events would then be dropped or sent after the token's completion.
- Core relays only while `current_request.request_ref == ref` and the tag matches
  (lib/gen_agent/server.ex:775-785). After interrupt, timeout, or finish, nothing is relayed for the
  ref. Queued cancel, halt-fail, pre_turn skip, and admission failure produce no events.
- Hex constraint `{:gen_agent, "~> 0.6.0 or ~> 0.7.0"}` (extensions/ensemble/mix.exs:46) admits core
  0.6.2, which predates #341. Core 0.6.2 ignores `stream_to:`, so events would be silently missing.

## Public API and message shape

`GenAgentEnsemble.tell_with_completion(name, prompt, recipient \\ self(), opts \\ [])` accepts one
new reserved option:

- `stream_to: pid | nil` (default `nil`). Popped from `opts` in `Server.tell_with_completion/4`
  before the call, so strategies never see it. A value that is not a pid or nil raises
  `ArgumentError` in the caller, matching core.
- `tell/3` and `ask/3` are unchanged. Streaming is opt-in only through `tell_with_completion`.

Each relayed event is one message to `stream_to`:

```elixir
{:gen_agent_ensemble, :event, session, token,
 %{agent: agent_name, dispatch: ordinal, event: %GenAgent.Event{}}}
```

- The 5-tuple prefix matches the existing `{:gen_agent_ensemble, :completion, session, token, result}`.
- `agent` is the bare member name, never the namespaced `"session/agent"`.
- `dispatch` is the existing per-token dispatch ordinal from `dispatch_contexts`, starting at 0. It
  separates repeated dispatches to the same agent within one token (Debate rounds, Supervisor
  coordinator before and after workers, Pipeline stages).
- The payload is a map so later fields can be added without breaking pattern matches.

Documented guarantees:

1. Only tokens opted in with `stream_to:` produce events. Child requests for other tokens are
   dispatched without `stream_to`, so core sends nothing for them.
2. For one child dispatch, events arrive in stream order.
3. All events for a token are sent before that token's completion message. If `stream_to` and
   `recipient` are the same process, they also arrive before it. Separate processes have no shared
   arrival order (same wording as core).
4. Across members of one token, events interleave in the order the ensemble received them. There is
   no cross-member ordering beyond that.
5. Nothing is sent for a token after its completion: success, error, cancel, dispatch rejection, or
   session halt. Events from members still running after an early terminal result (for example
   Consensus `reply_error` at consensus.ex:359 while peers are in flight) are dropped.
6. Best effort, no backpressure. A dead `stream_to` is ignored. It is not monitored and does not
   cancel the token. That matches the existing completion recipient.
7. Legacy unscoped `{:dispatch, agent, prompt}` ops have no token and are never streamed.

## Server changes (extensions/ensemble/lib/gen_agent_ensemble/server.ex)

1. **State:** add a field `stream_recipients: %{token => pid}` and initialize it to `%{}` in
   `init_impl`. Add it to `redact_state/1`.
2. **Call entry:** `tell_with_completion/4` pops and validates `:stream_to` and sends
   `{:tell, prompt, opts, recipient, stream_to}`. The 4-tuple `{:tell, prompt, opts, recipient}`
   clause delegates with `nil`, and the 3-tuple path is unchanged. In the 5-tuple handler, put the
   recipient into `stream_recipients` right after `start_token` and **before** `handle_tell`. The
   strategy's ops dispatch synchronously inside that call, so a later registration would miss the
   first dispatch.
3. **Dispatch opt-in:** in `dispatch/4`, use
   `opts = [on_halt: :fail] ++ if(Map.has_key?(state.stream_recipients, token), do: [stream_to: self()], else: [])`.
   The ensemble server is both the completion recipient and the stream recipient for the child. So
   per child ref, core's same-process guarantee applies: events reach the ensemble before the child
   completion.
4. **Relay clause** in `handle_info_impl/2`, placed before the catch-all:
   ```elixir
   defp handle_info_impl({:gen_agent, :event, _ns_agent, ref, event}, state) do
     with {:ok, {agent, token}} <- Map.fetch(state.in_flight, ref),
          {:ok, pid} <- Map.fetch(state.stream_recipients, token) do
       {_started_at, ordinal} = Map.fetch!(state.dispatch_contexts, ref)
       send(pid, {:gen_agent_ensemble, :event, state.session_name, token,
                  %{agent: agent, dispatch: ordinal, event: event}})
     end
     {:noreply, state}
   end
   ```
   This is the single fence. An event is forwarded only if its ref is still in `in_flight` (not
   completed, cancelled, agent-down, or stopped) and its token still has a recipient (not
   finished). Unknown, stale, or forged refs drop. The ref lookup ignores the namespaced name,
   as completions already do.
5. **Close on finish:** in `finish_token/3`, delete `stream_recipients[token]`. `reply_to_token`
   calls `finish_token` before it sends the completion, so no event can follow a completion.
6. **Ordered drain:** extend `drain_completions/1` so one `receive` matches both
   `{:gen_agent, :completion, _, _, _}` and `{:gen_agent, :event, _, _, _}`. A multi-pattern receive
   takes the first matching message in mailbox order, which keeps per-ref event-before-completion
   order during cancel. Each message goes through `handle_info_impl`. Rename the function to
   `drain_child_messages/1`, or keep the name and add a comment.

No strategy behaviour change. No `handle_stream_event` strategy callback in this slice. The issue
mentions one; it can be an additive follow-up once forwarding ships.

## Edge-case analysis

| Case | Behaviour | Why |
|---|---|---|
| Early child events before ref registration | Not possible | Core replies `{:ok, ref}` inside the call handler. Relays go out only when the agent later handles `{:gen_agent_stream, ...}`, and BEAM orders messages per sender pair, so the reply arrives first. Ensemble registers `in_flight` in the same callback, before it reads its mailbox again. If the call exits (`:dispatch_exit`), the ref is never registered and any events drop as unknown. |
| Multi-worker (Consensus, Supervisor, Pool, Debate, Pipeline) | Each child ref maps through `in_flight` to `{agent, token}`, with the ordinal from `dispatch_contexts` | All strategies use 4-tuple `:dispatch` (consensus.ex:142, supervisor.ex:118, pipeline.ex:90, debate.ex:144, pool.ex:71). |
| Child completion | Ref leaves `in_flight`, so later events drop | Core never relays after finish. This is defense in depth. |
| Token completion while peers run | Recipient removed in `finish_token`, so peer events drop | Guarantee 5. |
| Cancel, acknowledged | `fence_cancelled_ref` removes the ref, `finish_cancellation` removes the recipient | Core sends nothing after `interrupt_request` is acknowledged or a queued `cancel_request`. Already-queued events drop. |
| Cancel, unacknowledged or racing | `drain_completions` handles events and completions in mailbox order | Events that preceded a winning completion are forwarded before `{:error, :already_finished}` is decided. That is correct, because they preceded completion. |
| Halted child agent | `on_halt: :fail` admission gives `{:error, :halted}` and no ref. A queued halt-fail gives an error completion with no events | Core clauses at lib/gen_agent/server.ex:459 and 1675. |
| Session halt (`{:halt, _}` op) | `{:halt_session, _}` calls `reply_error` on every pending token, which clears all recipients before stop | |
| Agent down or `{:stop, agent}` | `drop_in_flight_for` removes refs, so events drop | |
| `stream_to` dead | `send/2` is a no-op. Token, poll, and await are unaffected | Not monitored, consistent with the completion recipient. |
| Non-opted token | No `stream_to` passed to core, so no messages | Zero overhead. |

## Core gap check

None demonstrated. Core already provides the per-ref ordering, the no-relay-after-finish rule, no
events for unstarted requests, and safe ref identity across agent restarts. The only cross-package
action is packaging. Raise the Hex constraint in extensions/ensemble/mix.exs:46 to the first core
release containing #341, and release core first. Under the path dependency used in development and
CI, this works now.

## Tests (new file extensions/ensemble/test/gen_agent_ensemble/stream_test.exs)

Add test support `GenAgentEnsemble.StreamingBackend` in test/support. It follows the core
`StreamToTest.Backend` pattern (test/gen_agent/stream_to_test.exs:6-55): a `"gated"` stream emits
one `:text` event, sends `{:gate, tag, task_pid}` to the observer, blocks on `:release` or
`{:release, :error}`, then emits more events and a `:result`. The `tag` is set per member, as in
`ControlledBackend`. Use `async: false`, the `start/2` and `on_exit` helpers from cancel_test.exs,
and `:sys.get_state(pid)` as a synchronous barrier before `refute_received`. No sleeps.

1. Solo, opted in: events tagged `%{agent: "w", dispatch: 0}` arrive in order, then the completion
   arrives (`stream_to == recipient`; assert exact message sequence with `receive` ordering).
2. Opt-out default: `tell_with_completion` without `stream_to`, and `tell/3`, produce no event
   messages. Assert that child `current_request.stream_to` is nil through `:sys.get_state` on the
   child.
3. Mixed tokens on Pool or Switchboard: token A opted in and token B not. Only A's events arrive,
   and none for B.
4. Separate `stream_to` process: it gets the events, and the completion goes only to the recipient.
5. Invalid `stream_to` raises `ArgumentError`. `stream_to` is not passed to `handle_tell` opts (a
   strategy in the test asserts on its opts).
6. Consensus multi-member: events from each member carry the right `agent`. Release one member
   with an error, so Consensus calls `reply_error`. Then release the peers. No peer event arrives
   after the completion.
7. Debate or Pipeline ordinals: repeated dispatches within one token carry increasing `dispatch`.
8. Cancel an active gated token: `{:ok, :cancelled}`, completion `{:error, :cancelled}`, no event
   after it. Inject a forged `{:gen_agent, :event, ns, ref, ev}` for the fenced ref and check it is
   dropped.
9. Cancel race: the child finishes before cancel (inject or release, then cancel). Events precede
   the completion, and the cancel result is `{:error, :already_finished}`. Covers the
   `drain_completions` ordering fix. Send events and a completion for the same ref to the server
   with `send/2`, then call `cancel`, then assert event order and that every event arrived before
   the completion.
10. Unknown ref and unregistered-ref events are dropped and do not crash the server (inject them).
11. Halted child: halt the member agent, then `tell_with_completion` with `stream_to`. Result is
    `{:error, {:dispatch_rejected, _, :halted}}`, and no events.
12. Session halt mid-stream: a strategy op `{:halt, r}` after one event. The completion is
    `{:error, {:halted, r}}`, and nothing follows it.
13. Agent down mid-stream: kill the child after the first event. Injected later events for its ref
    drop.
14. Dead `stream_to`: start and kill a process, use it as `stream_to`, and release. The token still
    completes for the recipient, and `poll` works.
15. Recipient cleanup: after every terminal path above, `:sys.get_state(pid).stream_recipients == %{}`.
16. `format_status` redacts `stream_recipients` (extend format_status_test.exs).

## Docs

- `tell_with_completion` @doc in extensions/ensemble/lib/gen_agent_ensemble.ex: describe `stream_to:`,
  the message shape, and guarantees 1-7.
- Ensemble CHANGELOG through release-please (feat commit). README section if streaming is
  documented there.

## Verification

From `extensions/ensemble`: `mix format --check-formatted`, `mix credo --strict`, `mix test`
(path dependency on core at df6d873), `mix dialyzer`. Run the core suite at the repo root so
`test/gen_agent/stream_to_test.exs` still passes. After core is released, check that
`GEN_AGENT_HEX=1 mix deps.get` resolves to a core version that includes #341.

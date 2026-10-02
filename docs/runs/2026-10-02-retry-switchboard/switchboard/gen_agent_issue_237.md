Found by the 2026-10-01 review at `b8f8ab4` and re-verified against `main` at `1a03608` by a read-only Codex worker in a `gen_agent_server` verification pool (genagent/gen_agent_server#25). One verifier per finding: treat file and line references as the starting point for the fix, and re-check them.

## Problem

### Switchboard facade {:error, :not_found} clauses are unreachable; unknown session names exit with :noproc

`inbox/2`, `summary_get/1` and `transcript/2` fall through to `{:error, :not_found}` when `GenAgent.status/1` does not return a SessionAgent state, and `send/2` also calls `status/1` first. `GenAgent.status/1` is a `:gen_statem.call` on a via tuple and exits for an unregistered name, so the fallback clauses never run and the caller crashes instead.

**Verification on current main.** I’ll check the facade’s branches and the `status/1` call path.

VERDICT: CONFIRMED

For an unregistered name, `GenAgent.status/1` calls `:gen_statem.call` through the registry and exits with `:noproc` before the facade can match a result (`lib/gen_agent.ex:808`, `lib/gen_agent.ex:879`). That affects `send/2`, `inbox/2`, `summary_get/1`, and `transcript/2` (`guides/patterns/switchboard.md:185`, `guides/patterns/switchboard.md:200`, `guides/patterns/switchboard.md:213`, `guides/patterns/switchboard.md:225`). Qualification: the `:not_found` branches can run if a registered agent has a different state type; they are unreachable specifically for missing names.

### Switchboard.send/2 shadows Kernel.send/2, has an undocumented return contract, and contradicts the Broadcast variation

Several small defects around the facade's `send/2`: the name collides with the auto-imported `Kernel.send/2`; the doc string lists two return values while the function has at least four; the busy check is a separate call from the tell; the check uses `status/1`, which copies the whole session history on every send; and the Broadcast variation tells the reader to rely on tell queueing while `send/2` rejects busy sessions. The usage example also writes `\\n` where a newline is intended.

**Verification on current main.** The facade defines `send/2`, shadowing the imported `Kernel.send/2` (guides/patterns/switchboard.md:184–185). Its doc lists two outcomes, but the code also returns `{:error, :halted}`, and `GenAgent.tell/2` can return an overload error (guides/patterns/switchboard.md:184–190; lib/gen_agent/server.ex:639–649). The separate `status` and `tell` calls leave a race; `status` returns `agent_state`, which contains the growing history (lib/gen_agent/server.ex:364–378; guides/patterns/switchboard.md:117–118). The broadcast variation recommends `send/2` while relying on queueing that its busy check prevents (guides/patterns/switchboard.md:186–190, 288–291). The example contains a literal `\\n` (guides/patterns/switchboard.md:280).

## Acceptance

- Tests cover each case above.


## Issue comment
Related findings from the same verification pool:

**Switchboard guide references a nonexistent halt/1 and has unreachable error branches**

The guide presented as the base for manager-driven UIs and MCP surfaces lists halt/1 as part of the public API, returns {:error, :not_found} from branches that cannot be reached for a missing agent, drops :name and :backend keys that are never present, and tells readers to enumerate an internal registry.

Verified on `main` at `1a03608`: I’m checking the guide’s examples against the API and registry behavior.

VERDICT: CONFIRMED

The guide lists `halt/1` as a `GenAgent` public API, but its own facade implements halting through `GenAgent.notify/2`; `GenAgent` has no `halt/1` (guides/patterns/switchboard.md:47-49, 239-240; lib/gen_agent.ex:690-692). The `:not_found` branches follow `GenAgent.status/2`, which calls `:gen_statem.call` and exits when the name is missing rather than returning a value those branches can match (guides/patterns/switchboard.md:200-215, 225-233; lib/gen_agent.ex:808-809). `:name` and `:backend` are removed before `init_agent/1`, making the guide’s `Keyword.drop` redundant (lib/gen_agent.ex:531-555; guides/patterns/switchboard.md:101). It also advises enumerating the registry (guides/patterns/switchboard.md:288-291).

**Switchboard guide inbox loses the result of an in-flight turn and has unreachable not_found branches**

The guide reads unread items through `GenAgent.status/2` and then acknowledges with `notify(name, :ack_inbox)`, whose handler sets the cursor to `length(history)` when it runs. If a turn is in flight, the notify is deferred until after `handle_response/3` has appended that turn, so the turn is marked read without ever being returned. The guide also matches `GenAgent.status(name)` against a fallback `{:error, :not_found}` clause, but `status/2` exits with `:noproc` for an unknown name.

Verified on `main` at `1a03608`: I’m checking the inbox example and the server’s notification ordering.

VERDICT: CONFIRMED

When `inbox(name, ack: true)` returns at least one unread item, it sends `:ack_inbox` after reading `status/2` (guides/patterns/switchboard.md:196-204). If a turn is processing, the server queues that notification (lib/gen_agent/server.ex:419-420, 763-770), appends the turn through `handle_response/3`, then drains notifications (lib/gen_agent/server.ex:1255-1284). The guide’s handler advances the cursor to the **new** history length, so the in-flight result can be skipped without appearing in the returned items (guides/patterns/switchboard.md:106-118, 141-143). For an unknown name, `status/2` calls `:gen_statem.call`; it exits rather than reaching the guide’s `:not_found` fallback (lib/gen_agent.ex:808-809; guides/patterns/switchboard.md:206-207).

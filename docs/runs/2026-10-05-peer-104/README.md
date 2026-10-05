# Peer diagnostics follow-up: server #104

Issue: https://github.com/genagent/gen_agent_server/issues/104
PR: https://github.com/genagent/gen_agent_server/pull/107

## Worker scope and control

The user requested a separate session to double backlog capacity:

> lets see if we can fork a session to double our capacity on the gen_agent backlog. best case: you or i fork the session, then you hand that session a slice of work that it can work on in parallel with us without too many conflicts

The parent retained core #119; this fork owned only server #104. Its task was
to use a fresh isolated checkout, inspect #103, open a scoped draft before
implementation, reproduce and fix binding verification, acceptor crash retry,
and terminal channel diagnostics, update the peers resource, test and merge
when green. Transport, reconciliation, retention, cancellation, wrappers and
other checkouts remained outside the task. Scheduled upkeep stayed paused.

No GenAgent worker spec or provider prompt was executed. This was a direct
Codex application session; no CLI model/effort override or paid Claude/Codex
call was used. Do not infer a CLI provider/model from the host session name.
The existing-session native evidence from #103 was not repeated.

Isolation: fresh clone of current main in
`/private/tmp/gen_agent_server_104_20261005`, branch `fix/peer-diagnostics-104`.
The original server checkout was 55 commits behind and stayed untouched.
An empty branch commit allowed draft #107 to open before implementation.
The app attachment attempt failed at the inherited 100-attachment limit;
the GitHub PR itself was created successfully.

## Reproduction, implementation and review evidence

New regression tests against unchanged source reproduced four failures:
the recovering single candidate returned `ambiguous_peer`, the acceptor
respawned immediately, and terminal channels still reported `active` in
two result scenarios. The fixture-only command was:

```sh
mix test test/gen_agent_server_peers_test.exs --exclude native_process
```

Selection now retains `{candidate, verification}` pairs. It keeps a sole
rejection, ignores stale artifacts when exactly one live claim verifies,
and still rejects multiple live claims. Successful binding publication and
delivery retain their separate generation checks.

Acceptor EXIT recovery uses a nonblocking timer with 100, 200, 400, 800 and
1000 ms delays, capped at 1000 ms. An accepted connection resets the delay.
The listener is checked again when the timer fires; listener loss fails
closed. Shutdown cancels a pending timer and tolerates a missing acceptor.
Tests observe timer state, ledger responsiveness, the cap, reset, shutdown
and listener loss using fixture Unix sockets.

Terminal public records derive `reply_channel=settled` from their state,
including older persisted records. Pending records retain active/lost or
report unavailable when the listener fails. Tests cover completed, blocked
and failed results, listener loss, durable restart and repeatable reads.
The MCP peers resource documents all values and refreshed binding diagnostics.

Source review checked the successful-candidate rechecks, terminal-before-
listener precedence, bounded timer lifecycle and existing returned-error
retry. No transport or ledger format change was introduced.

The initial full suite passed 125 tests. Adding the shutdown/listener-loss
checks exposed an existing durable-restart teardown race: a linked fixture
could exit between `Process.alive?` and an `on_exit` stop. Those fixtures now
use ExUnit supervision. The failed run reported 126/127 passing; it is not
counted as successful validation.

## Acceptance commands

```sh
mix deps.get
mix compile --warnings-as-errors
mix format --check-formatted
mix test
mix run examples/ensemble_patterns.exs
mix gen_agent_server ask echo ci
MIX_QUIET=1 mix gen_agent_server.ops instances
MIX_ENV=prod mix release
MIX_ENV=prod mix run examples/mcp_release_smoke.exs
_build/prod/rel/gen_agent_server/bin/gen_agent_server eval 'Application.ensure_all_started(:gen_agent_server); case GenAgentServer.ask("echo", "release") do {:ok, %{text: "echo: release"}} -> :ok; other -> raise inspect(other) end'
```

The local OS-generation test only inspects the current BEAM process; it does
not message an existing provider session. Echo examples and packaged MCP
checks do not call providers. CI repeats the required checks on Linux.
Final suite and exact-head CI outcomes are recorded in the PR.

No release workflow, version bump or tag is part of this fix. The local
release build validates packaging; it is not a published release.

## Pattern retained

Give a fork one issue in a separate repository, preserve the parent-owned
issue, claim before work and use a current-main isolated clone. Keep the
reproduction, host validation and CI results distinct. A fork adds capacity
only if ownership and writable surfaces stay explicit. Retain failed runs
and corrective test changes alongside the final validation.

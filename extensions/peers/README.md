# gen_agent_server peers extension

Optional, experimental messaging to existing Claude Desktop Code sessions for
[gen_agent_server](../../README.md). Listing the extension starts
`GenAgentServer.Peers` and adds the `discover_peers`, `bind_peer`,
`send_peer_message`, and `peer_result` operations to `GenAgentServer.Ops`.

```elixir
# mix.exs
{:gen_agent_server_peers, path: "path/to/gen_agent_server/extensions/peers"}

# config/config.exs
config :gen_agent_server, extensions: [GenAgentServer.Peers]

# config/runtime.exs
config :gen_agent_server, :peers,
  enabled: System.get_env("GEN_AGENT_SERVER_PEERS", "false") == "true",
  store: System.get_env("GEN_AGENT_SERVER_PEER_STORE"),
  claude_home: System.get_env("GEN_AGENT_SERVER_CLAUDE_HOME", Path.expand("~/.claude"))
```

## Existing Claude Desktop Code peers (experimental)

Set `GEN_AGENT_SERVER_PEERS=true` to enable the four peer tools. This initially
supports native protocol 1 on macOS with Claude Code 2.1.286 and 2.1.288;
unobserved versions are rejected. The wire framing is experimental. Discovery
reads `~/.claude/sessions` (operator override: `GEN_AGENT_SERVER_CLAUDE_HOME`).
The server verifies native identity, process generation and owned socket before
binding and every delivery, and never starts, resumes or stops the external session.

1. `discover_peers` with `{"name":"some-session"}`.
2. `bind_peer` with `{"address":"claude://some-session","session_id":"<discovered ID>"}`.
3. `send_peer_message` with the address, a bounded `message` and a stable
   task `idempotency_key`. Save the returned random `id`.
4. `peer_result` with that `id`. Native SendMessage replies return to the server's
   private inbox; the recipient needs no bridge MCP install or scheduled poll.

A successful socket write is `queued`, with execution `unknown`. Explicit native
acknowledged/running/completed/blocked/failed replies are correlated peer reports.
They do not verify work quality. Repeating the same key/payload never sends again;
changed payloads conflict. Missing reply, timeout or uncertain delivery requires
reconciliation using that original key/ID, with no automatic new-key retry.

By default the ledger is volatile. Set `GEN_AGENT_SERVER_PEER_STORE` to an absolute
private JSON path for atomic owner-only persistence; each server needs its own file.
The store contains task/reply text. Completed replies survive restart; outstanding
requests become `delivery_uncertain` when the old reply channel ends, and are never
replayed. Bind explicitly to refresh the same native ID after process restart.
Bounds and operating details are in `gen-agent://guide/peers`.

The caller checks pending results during its delegation turn. Idle Codex Desktop
wakeup, a general Codex peer adapter, shared HTTP transport, retention/eviction,
scheduling controls, and a dashboard remain follow-on work.

The [dogfooding log](docs/dogfooding.md) records bounded real tasks, observed
issues, and the planned progression through Ensemble patterns.
The [control-pattern inventory](docs/control-patterns.md) points to executable
examples and records the repeated control steps that may become an optional
higher-level module.

For a local, model-free look at server-managed Pipeline and Supervisor
patterns, run `mix run examples/ensemble_patterns.exs`. The example checks
stage handoff, two-worker fan-out, result IDs, and worker cleanup inside the
same OTP application.

For a real read-only review, run
`mix run examples/claude_codex_review.exs /path/to/project "Review the remote command handling"`.
Codex drafts findings and Claude verifies them against the same project through
a managed Pipeline. Both CLIs must be locally authenticated. This example
returns the final verified response; intermediate stage text is not retained
by the server result API.

For two to four independent read-only Codex reviews in parallel, run
`mix run examples/codex_parallel_review.exs /path/to/project "Review file A" "Review file B"`.
Pass a third or fourth task in the same form when needed. An Echo coordinator
splits the supplied tasks deterministically; the managed Supervisor labels
each worker response and stops the workers after completion.

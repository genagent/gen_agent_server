# Server MCP 0.1.0 implementation run

This run added a local stdio MCP adapter over the existing `GenAgentServer.Ops`
catalogue. The first tool surface is deliberately limited to `instances`,
`agents`, `status`, `invoke`, `result`, and `ask`.

The exact task and constraints are in `issue.md` and `notes.md`.
`initial-config.json`, `revision-config.json`, and `final-review-config.json`
record the requested provider/model and control flags for each pass;
`issue_handoff_used.exs` is the control program that assembled the prompts and
ran the named stages on one server instance. Codex Astra triaged, Claude Sonnet 5.5 implemented and
revised, and Codex Astra reviewed. The stage Markdown and JSON files retain
the responses, actual model identities, session IDs, timing, and usage. The
checkout was isolated at `/tmp/gen_agent_server_mcp_010_20261002`; the dirty
`gen_agent_mcp` checkout was left untouched.

The first implementation stopped at an `Ops` edit because the worker could
not read Snodo's external checkout. The caller fetched published Snodo 0.4.0
into this project's `deps/snodo` and supplied verified API signatures. A
second implementation produced the adapter; review found incorrect Snodo
result wrapping, startup configuration, test expectations, and premature
version advertising. The revision fixed those. A subsequent review found
Snodo's default 30-second stdio request deadline could cut off longer `ask`
calls. The caller changed the transport deadline to `:infinity`, retaining
the server's own ask timeout and GenAgent watchdog, and the final independent
review approved.

Host checks on Snodo 0.4.0 passed: formatting, warnings-as-errors compilation,
10 focused MCP tests, all 71 server tests, the managed Echo Pipeline and
Supervisor example, an OTP release build, and a real stdio MCP client against
that built release. The client discovered six tools, asked Echo, invoked Echo,
and read the same completed result twice. The same built release then handled
one live MCP `ask` through Codex and one through Claude with `READY` replies
and session IDs; `real_provider_probe.exs` records the exact control code.
Codex completed in 4,429 ms and Claude in 3,055 ms. Publication against
Snodo 0.4.1 remains a release gate.

Mechanical observations: a worker's source visibility must be checked before
implementation; the Snodo tool callback uses `{:ok, result}`; the stdio
transport has an independent execution deadline; a fresh Mix task must load
runtime config explicitly. Behavioral guidance in the issue and notes did
not enforce these contracts. The host compiled and exercised them outside the
model responses. `revise` and `review_only` overwrote active stage files, so
the caller preserved each round's files here; a future control API should
archive rounds automatically.

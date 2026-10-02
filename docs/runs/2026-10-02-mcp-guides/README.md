# MCP guide catalogue and release probe

The server's nine-tool MCP allowlist was already released in 0.2.0. This run
adds a fixed guide index and three focused guides while retaining the existing
quickstart. All resource text is compiled into the release; no project files
or arbitrary URIs are served. No provider turn was started in the orientation
probes.

Validation in the isolated `/tmp/gen_agent_server_mcp_guides` checkout:

- `mix format`, `mix compile --warnings-as-errors`, and `mix test`: 84 passed.
- `MIX_ENV=prod mix release` assembled 0.3.0, and
  `MIX_ENV=prod mix run examples/mcp_release_smoke.exs` passed against the
  packaged stdio release. The smoke client checked both 2026-07-28
  `server/discover` and 2025-11-25 `initialize`, the complete resource list,
  and tool invocation/result behavior.
- Codex `gpt-6-luna`, read-only and ephemeral, with a temporary MCP command
  pointing to this packaged release, listed resources, read the index and
  invocation guide, and correctly selected `invoke` then repeatable `result`
  for long work. It also identified that another MCP connection cannot read
  this connection's state.
- Claude Haiku, `dontAsk`, no session persistence, with a temporary strict MCP
  config pointing to the same release, read the index and capability guide.
  It correctly named `create_instance` as the model-selection path and said
  schedules are not editable through MCP.

The exact orientation prompts were:

> Use only the gen_agent_server MCP resources. Read
> gen-agent://guide/index and the guide about invocation. In two sentences,
> explain which tools to use for a long task and what state another MCP
> connection can read. Do not call shell or invoke any agent.

> Use only gen_agent_server MCP resources. Read gen-agent://guide/index and the
> guide about capabilities. In two sentences, explain how to choose a model
> and whether you can create schedules through MCP. Do not call shell or invoke
> any agent.

The client commands used the packaged release as the MCP command with args
`["eval", "GenAgentServer.MCP.serve()"]`. Codex approved MCP tools only in
that ephemeral run; Claude allowed only the GenAgent Server MCP namespace and
disallowed shell and edit tools. Both clients exited after the probe.

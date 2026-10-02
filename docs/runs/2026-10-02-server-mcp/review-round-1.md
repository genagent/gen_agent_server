I’ll inspect the diff and surrounding code, then check it against the MCP milestone and existing caller behavior.

REQUEST CHANGES

- **[P1] MCP milestone is unimplemented — `lib/gen_agent_server/ops.ex:186`, `mix.exs:18`.** The only change adds trusted source context to Ops. There is no Snodo dependency, six-tool MCP catalogue, stdio server, Mix entry point, or release entry point. Claude/Codex clients still cannot discover or invoke this server through MCP. Complete these using verified published Snodo 0.4.0 APIs.

- **[P1] Required acceptance coverage is missing — `test/gen_agent_server_ops_test.exs:1`.** Existing tests exercise Ops directly; no MCP tests were added for discovery, invocation, repeatable reads, unknown routes/instances, or independent instances. Also verify MCP telemetry uses `:mcp` while existing callers retain `:api`, and exercise stdio if practical.

- **[P2] Setup documentation remains absent — `README.md:246`, `README.md:282`.** The README still defers MCP and makes cancellation a prerequisite. Add exact checkout and OTP-release MCP setup instructions, including how stdout remains protocol-only.

The source propagation change is consistent with the underlying invocation API and preserves default `:api` behavior by inspection. Version remains `0.1.0-dev`. No tests were run.
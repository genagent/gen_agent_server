Goal: ship a useful first GenAgent Server 0.1.0 with a Snodo-backed MCP surface. The server already exposes typed operations through GenAgentServer.Ops and has an instance-scoped invocation/result API. Add a local stdio MCP entry point so a Claude or Codex MCP client can list instances/routes, submit work, and read repeatable results. This is the explicitly authorized 0.1.0 MCP milestone; session-to-session mailbox/bridge, HTTP transport and broader control operations are separate follow-ups.

Acceptance:
- Use published Snodo 0.4.0 APIs so implementation can be tested now. Snodo 0.4.1 is pending release; do not change Snodo itself.
- Allowlist only instances, agents, status, invoke, result and ask in the first MCP catalogue. Do not expose arbitrary GenAgentServer.Ops.call names, run_pattern, stop_instance, host paths, raw OTP calls, or dynamic configuration.
- MCP invoke/ask must mark telemetry source :mcp. Preserve existing Ops callers' behavior.
- Make the stdio entry point usable from a Mix checkout and from an OTP release. Never print non-protocol output on stdout after MCP starts. Document exact setup.
- Add provider-free direct MCP acceptance tests for discovery, invocation, repeatable result reads, unknown route/instance errors, and two independent instances. Exercise a real stdio transport if practical.
- Keep version 0.1.0-dev for this code PR; release bump is separate after integration and Snodo 0.4.1 publication.

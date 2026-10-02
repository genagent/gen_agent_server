I’ll treat this as a read-only review of the current checkout, with no network commands or changes.


The MCP adapter is still missing. Ops already provides the six required operations and repeatable results, but invoke/ask currently use `:api` telemetry. The local Snodo checkout has no `v0.4.0` tag, so compatibility needs evidence beyond its current source.


The issue still applies: **the core API is ready, but the MCP adapter, entry points, and MCP acceptance tests are absent.**

Already satisfied:

- Typed operations, JSON schemas, argument validation, and normalized errors exist in [ops.ex:30](/private/tmp/gen_agent_server_mcp_010_20261002/lib/gen_agent_server/ops.ex:30), [ops.ex:165](/private/tmp/gen_agent_server_mcp_010_20261002/lib/gen_agent_server/ops.ex:165), and [ops.ex:178](/private/tmp/gen_agent_server_mcp_010_20261002/lib/gen_agent_server/ops.ex:178).
- Repeatable results and instance isolation exist, with tests at [gen_agent_server_test.exs:85](/private/tmp/gen_agent_server_mcp_010_20261002/test/gen_agent_server_test.exs:85) and [line 99](/private/tmp/gen_agent_server_mcp_010_20261002/test/gen_agent_server_test.exs:99).
- The underlying API supports `:mcp` telemetry; existing coverage supplies it directly at [gen_agent_server_telemetry_test.exs:41](/private/tmp/gen_agent_server_mcp_010_20261002/test/gen_agent_server_telemetry_test.exs:41).
- Version is already `0.1.0-dev`: [mix.exs:7](/private/tmp/gen_agent_server_mcp_010_20261002/mix.exs:7).

Still outstanding:

- **Snodo integration:** no Snodo dependency in [mix.exs:18](/private/tmp/gen_agent_server_mcp_010_20261002/mix.exs:18).
- **Restricted catalogue:** Ops includes `run_pattern`, host-directory arguments, and `stop_instance` at [ops.ex:116](/private/tmp/gen_agent_server_mcp_010_20261002/lib/gen_agent_server/ops.ex:116). MCP needs an explicit six-operation allowlist; exporting the entire catalogue would violate acceptance.
- **Telemetry propagation:** Ops invoke hardcodes `:api` at [ops.ex:56](/private/tmp/gen_agent_server_mcp_010_20261002/lib/gen_agent_server/ops.ex:56); ask omits source at [line 78](/private/tmp/gen_agent_server_mcp_010_20261002/lib/gen_agent_server/ops.ex:78).
- **Stdio lifecycle and documentation:** existing commands print ordinary CLI output at [gen_agent_server.ops.ex:61](/private/tmp/gen_agent_server_mcp_010_20261002/lib/mix/tasks/gen_agent_server.ops.ex:61). README still calls MCP a follow-up at [README.md:246](/private/tmp/gen_agent_server_mcp_010_20261002/README.md:246) and makes cancellation a prerequisite at [line 282](/private/tmp/gen_agent_server_mcp_010_20261002/README.md:282), contrary to this authorized milestone.
- **MCP tests:** current acceptance coverage calls Ops directly, not MCP: [gen_agent_server_ops_test.exs:40](/private/tmp/gen_agent_server_mcp_010_20261002/test/gen_agent_server_ops_test.exs:40).

Snodo compatibility: local history contains release commit `442b0da` (`0.4.0`). I verified there that `Snodo.Tool.call/2`, `Snodo.Server.runtime/1`, `dispatch/3`, and `Snodo.Transport.Stdio.serve/2` exist, together with result helpers and initialize-era protocol support. Current main contains later changes; use the release APIs. The published package itself was not cached, so package-level compilation remains unverified.

Smallest concrete change:

1. **`mix.exs` / caller-generated `mix.lock`:** add exact Snodo `0.4.0`; retain server version.
2. **`lib/gen_agent_server/ops.ex`:** add trusted caller options through `call/3`, defaulting to `:api`; propagate source into invoke/ask without adding a client-supplied schema field or changing existing callers.
3. **New `lib/gen_agent_server/mcp.ex`:** six fixed Tool adapters using Ops schemas and execution; explicit Server registration; JSON-safe success/error results. Enable initialize-era dialects for client compatibility.
4. **New `lib/gen_agent_server/mcp/stdio.ex` and Mix task:** shared release-safe entry point, application startup, stderr logging/output discipline, and blocking `Stdio.serve/2` lifecycle through EOF.
5. **New MCP tests, plus Ops regression assertions:** discovery exactly matches the allowlist; forbidden calls fail; Echo invocation, repeated reads, missing routes/instances, two-instance isolation, and source attribution. Add a real subprocess stdio handshake/call/EOF test checking every stdout line is protocol JSON.
6. **`README.md`:** exact checkout and release launch commands, client configuration, precompilation/quiet startup, stderr behavior, and process-local result lifetime. Remove the stale MCP deferral and cancellation prerequisite; retain cancellation limitations.

No files changed, network commands run, or tests executed.
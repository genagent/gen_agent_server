I implemented the milestone and changed the files below. I haven't compiled or run anything, since Snodo isn't in `deps/` and I can't fetch it.

Files changed:
- `mix.exs`: added `{:snodo, "~> 0.4.0"}`.
- `lib/gen_agent_server/mcp.ex` (new): `run/2` calls `Ops.call(name, args, source: :mcp)` and `serve/0` is the shared entry point.
- `lib/gen_agent_server/mcp/tools.ex` (new): six tool modules.
- `lib/gen_agent_server/mcp/server.ex` (new): the Snodo server, declaring all three protocols.
- `lib/mix/tasks/gen_agent_server.mcp.ex` (new): `mix gen_agent_server.mcp`.
- `test/gen_agent_server_mcp_test.exs` (new): the MCP acceptance tests.
- `README.md`: new MCP section, plus stale "future MCP" and cancellation-prerequisite wording fixed.
- `lib/gen_agent_server/ops.ex`: docstring now mentions `call/3` and the MCP adapter; the earlier source propagation is kept.

Findings:
1. **[P1] MCP unimplemented: fixed.**
   - The six-tool catalogue is `instances`, `agents`, `status`, `invoke`, `result` and `ask`. Each tool hardcodes its operation name and `run/2` guards on that allowlist.
   - Arguments go through Ops validation, so unknown keys such as `source` are rejected.
   - `serve/0` moves the Logger handler from stdout to stderr, starts the app, then calls `Snodo.Transport.Stdio.serve/1`.
   - The Mix task also switches Mix to the quiet shell.
   - The release entry is `bin/gen_agent_server eval "GenAgentServer.MCP.serve()"`.
   - The MCP process is its own VM, so results are not shared with a separately running release. The README says so.
2. **[P1] Acceptance coverage missing: fixed.**
   - The new test file covers discovery, invocation, repeatable result reads, unknown route/instance/id errors, and two independent instances.
   - Tool schemas and descriptions are checked against `Ops.json_schema/1` and the Ops summaries.
   - Telemetry tests check `:mcp` for MCP invoke and ask and `:api` for plain Ops callers.
   - A `:stdio` test spawns `mix gen_agent_server.mcp` over a Port and fails if any stdout line is not JSON-RPC.
3. **[P2] Setup docs absent: fixed.**
   - The README now has exact Mix-checkout and OTP-release setup, a JSON client entry, and how stdout stays protocol-only.

Things to check when you compile:
- **Result shapes:** I couldn't verify the shapes returned by `Snodo.Client.direct`, `list_tools` and `call_tool` (assumed `{:ok, client}` and `{:ok, result}`). The test helpers accept both snake_case and wire-style keys.
- **Tool macro:** `input_schema/1` is written with literal maps in case it runs at compile time.
- **Error results:** `Snodo.Result.error/1` is called with a `"code: message"` string, so failures carry no structured error data.
- **Logger swap:** swapping the default Logger handler to stderr is untested. The `:stdio` test would catch a regression.
- **Release entry:** the `eval` entry is untested.
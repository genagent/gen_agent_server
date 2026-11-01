# gen_agent_server patterns extension

Optional Ensemble pattern runs from JSON specs for
[gen_agent_server](../../README.md). Listing the extension adds the `patterns`
and `run_pattern` operations to `GenAgentServer.Ops`; `mix gen_agent_server.run`
runs a spec file in a fresh local application.

```elixir
# mix.exs
{:gen_agent_server_patterns, path: "path/to/gen_agent_server/extensions/patterns"}

# config/config.exs
config :gen_agent_server, extensions: [GenAgentServer.Patterns]
```

`GenAgentServer.PatternSpec` describes the spec format; `GenAgentServer.Run`
starts a temporary instance, submits every prompt before awaiting results, and
stops the instance when the run finishes, including on timeout.

```sh
mix gen_agent_server.run examples/specs/echo/pool.json \
  --prompt "Check one claim" --prompt "Check another claim"
MIX_QUIET=1 mix gen_agent_server.ops patterns
MIX_QUIET=1 mix gen_agent_server.ops run_pattern \
  --spec @examples/specs/echo/pool.json --prompts "Check a claim" --remote
```

Pattern instances started directly with `GenAgentServer.start_pattern_instance/5`
are part of the base server and do not need this extension. `run_pattern` is
not on the MCP allowlist.

CLI agents default to inherited access: server permission, tools, sandbox, and
user-config overrides are omitted. Settings belong to the server process user;
transient client permissions are not transferred. Headless sessions cannot
answer prompts, and Codex retains approvals disabled. Access depends on CLI
settings and host permissions. Specs accept `claude_permission_mode` values
`inherit`, `read_only`, `plan`, `accept_edits`, `auto`, `bypass_permissions`, and
`dont_ask`; `codex_sandbox` accepts `inherit`, `read_only`, and `workspace_write`.
`codex_user_config` accepts `inherit` (default) and `ignore` independently.

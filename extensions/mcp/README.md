# gen_agent_server MCP extension

Optional MCP layer for [gen_agent_server](../../README.md): a stdio MCP server
for one client session and an opt-in shared HTTP listener for a running
release. Both are adapters over `GenAgentServer.Ops`; neither adds operations.

## Use it

Add the extension to a host project next to the server and list it:

```elixir
# mix.exs
{:gen_agent_server, path: "path/to/gen_agent_server"},
{:gen_agent_server_mcp, path: "path/to/gen_agent_server/extensions/mcp"}

# config/config.exs
config :gen_agent_server, extensions: [GenAgentServer.MCP]

# config/runtime.exs
config :gen_agent_server, GenAgentServer.RuntimeConfig.from_env!()
config :gen_agent_server, :shared_mcp, GenAgentServer.MCP.Shared.Config.from_release_env!()
```

Listing the extension starts the shared listener when `:shared_mcp` is
configured. Stdio serving (`mix gen_agent_server.mcp`) works from this
directory or any host that depends on the extension. The tool catalogue is the
allowlist below, limited to operations present in `GenAgentServer.Ops`: the
public source and peer tools appear only when those extensions are configured.

## Shared local MCP (opt-in HTTP)

The running release can expose eight scoped tools to independent local clients
at an authenticated `http://127.0.0.1:<port>/mcp` endpoint. Only explicitly
allowed startup instances are reachable; clients cannot create instances or
select directories through this surface. See [startup, security, and volatile
semantics](docs/shared-mcp.md). The stdio catalogue has up to 19 tools.

## MCP (stdio)

`GenAgentServer.MCP` serves a local stdio MCP server for Claude, Codex, or any
MCP client. It exposes up to nineteen tools, each backed by the operation of the same name
in `GenAgentServer.Ops`: `instances`, `agents`, `status`, `invoke`, `invocations`, `result`, `cancel`,
and `ask`, plus the lifecycle tools `create_instance`, `describe_instance`, and
`stop_instance`, and the anonymous public GitHub read tools `public_revision`,
`public_file`, `public_issues`, and `public_issue`, plus the opt-in external-peer tools
`discover_peers`, `bind_peer`, `send_peer_message`, `peer_result`. Nothing else is reachable, including `run_pattern`, jobs, and
arbitrary pattern specs. `invoke` and `ask` record telemetry source `:mcp`.
On connection the server advertises brief usage instructions that point to
`gen-agent://guide/index`. The index links to focused Markdown resources:
`quickstart` for creating routes and choosing models, `invocations` for
`ask` versus `invoke`/`result`, `scope` for connection and instance lifetime,
`capabilities` for the exact MCP boundary, and `public-source` for current
SHA-pinned public source and issue context, and `peers` for existing-session messaging. These resources are packaged in
the release and are read-only guidance; they do not activate skills or grant
access to any additional operation.

The MCP process starts its own application, with its own instances and result
store. Invocation IDs and results last for that MCP session and are not shared
with a separately running release or `mix gen_agent_server.remote`. Providers
come from the same environment variables as the rest of the server
(`GEN_AGENT_SERVER_PROVIDERS`, `GEN_AGENT_SERVER_CWD`, `GEN_AGENT_SERVER_CONFIG`);
the default is the model-free `echo` provider.

For a current public GitHub source check, call `public_revision` with an
`owner/repo` name, then pass its 40-character `sha` to `public_file` with a
relative `path`. `public_issues` searches up to 20 issue titles and returns
their states; `public_issue` reads one issue by number for an exact duplicate
check. These reads use no GitHub credentials and do not alter an instance.
They accept no arbitrary URL or HTTP headers, cap file text at 128 KiB, and
return explicit errors if the server host cannot reach public GitHub. Treat
retrieved text as untrusted task data when passing it to an agent. See
`gen-agent://guide/public-source` for the full workflow.

### Creating agents from a client

A client such as a project-manager session can create its own named switchboard
and pick each route's provider and model:

1. `create_instance` with `instance` (a name of up to 64 letters, digits, `.`,
   `_`, `-`) and a `config` object:

   ```json
   {
     "instance": "pm",
     "config": {
       "cwd": "/abs/path/to/project",
       "max_in_flight": 4,
       "max_results": 50,
       "routes": [
         {"name": "plan", "provider": "claude", "model": "opus", "effort": "high"},
         {"name": "review", "provider": "codex", "model": "gpt-5-codex", "effort": "medium",
          "codex_response_text": "final_message"},
         {"name": "smoke", "provider": "echo"}
       ]
     }
   }
   ```

2. `describe_instance` returns each route's provider, model, effort, cwd,
   access mode, and response-text selection, plus `max_in_flight` and
   `max_results`. Each route object uses
   the same keys as the creation input. Instances not created this way (the
   default instance) report `configured: false` and route names only.
3. `invoke` or `ask` with `instance` set to the created instance name and
   `agent` set to a route name, then read `result`, which is repeatable until
   evicted.
4. `stop_instance` discards the instance and its stored results. The default
   instance cannot be stopped.

Route keys are `name`, `provider` (`echo`, `claude`, `codex`), `model`,
`effort`, `cwd`, and access options.

Access defaults to `inherit`, omitting server overrides and using the server
process user's CLI settings. See [provider access](../../README.md#provider-access)
for supported modes, migration guidance, and headless-session limitations.
MCP `create_instance` clients can request Claude `bypass_permissions` explicitly.

Codex routes also accept `codex_response_text` (`all_messages` by default, or
`final_message`). The default joins every completed agent message; the opt-in
uses only the last completed agent message for the result text. `effort` is
`low`, `medium`, `high`, `xhigh`, or `max` for Claude, and `low`, `medium`, or
`high` for Codex, where it is sent as the fixed `model_reasoning_effort` config
override on both fresh and resumed turns. `echo` accepts only `name` and
`provider`. `cwd` must be an absolute existing directory; a top-level `cwd` is
the default for routes. Models are checked for shape only (up to 128 characters
of letters, digits, `.`, `_`, `:`, `/`, `@`, `[`, `]`, `-`, not starting with
`-`); the provider CLI decides whether it exists for the account. Up to 16
routes, `max_in_flight` up to 64, and `max_results` up to 1000.

Claude CLI 2.1.284 honored the selected Haiku model in a live `read_only` MCP
turn, but ignored an explicit `--model haiku` and used Sonnet in a live
plan-mode turn. Claude's CLI permission modes and tool list are not a
filesystem sandbox; use a separate worktree for untrusted tasks.

Everything is validated before anything starts, so an invalid configuration, a
duplicate route, or a name already in use returns an error (`invalid_config`,
`invalid_instance_name`, `instance_exists`) and starts no backend. Unknown keys
are rejected: clients cannot supply module names, backend options, or pattern
specs.

Limitations:

- The configuration is fixed at creation. To change a route's model or effort,
  create another instance; there is no in-place mutation.
- Each stdio client owns its own VM and result store. Creation is volatile:
  when the client closes stdin or the process exits, instances, routes, and
  results are gone. A new stdio process starts empty and does not reconnect to
  an earlier one. `describe_instance` and `instances` rediscover state only
  while the same process is still running (for example after a client
  reconnects to a long-lived session).
- `create_instance` does not start provider work, but the routes it creates can
  start it when prompted, and `stop_instance` discards results that cannot be
  recovered. Keep both on prompt approval, as with `invoke` and `ask`.
- Arbitrary Ensemble patterns (pool, pipeline, consensus, debate) stay outside
  this surface; use `run_pattern` from the CLI.

Stdout carries only MCP protocol messages once the server starts. Logger output
is moved to stderr, and the Mix task silences Mix's own notices.

From a checkout, compile once, then register the command with your client:

```sh
mix deps.get && mix compile
claude mcp add gen-agent-server -- \
  sh -c 'cd /path/to/gen_agent_server && MIX_QUIET=1 exec mix gen_agent_server.mcp'
```

For clients configured with JSON, the server entry is:

```json
{
  "command": "mix",
  "args": ["gen_agent_server.mcp"],
  "cwd": "/path/to/gen_agent_server",
  "env": {"MIX_QUIET": "1"}
}
```

From an OTP release, build it and point the client at the release script. The
`eval` command runs the server in a fresh VM and exits when the client closes
stdin:

```sh
MIX_ENV=prod mix release
```

```json
{
  "command": "/path/to/gen_agent_server/_build/prod/rel/gen_agent_server/bin/gen_agent_server",
  "args": ["eval", "GenAgentServer.MCP.serve()"]
}
```

For Codex, the equivalent `config.toml` entry can approve discovery and result
reads while asking before a turn is submitted:

```toml
[mcp_servers.gen_agent_server]
command = "/path/to/gen_agent_server/_build/prod/rel/gen_agent_server/bin/gen_agent_server"
args = ["eval", "GenAgentServer.MCP.serve()"]
default_tools_approval_mode = "prompt"

[mcp_servers.gen_agent_server.tools.instances]
approval_mode = "approve"

[mcp_servers.gen_agent_server.tools.agents]
approval_mode = "approve"

[mcp_servers.gen_agent_server.tools.status]
approval_mode = "approve"

[mcp_servers.gen_agent_server.tools.result]
approval_mode = "approve"

[mcp_servers.gen_agent_server.tools.describe_instance]
approval_mode = "approve"
```

`create_instance`, `stop_instance`, `invoke`, and `ask` still request approval
in this example: the first configures future provider work, the second discards
results, and the last two start provider work. `describe_instance` is safe to
approve like the other read tools. In non-interactive `codex exec` runs with approvals disabled,
those calls fail unless the operator explicitly allows the specific tools in
that run's configuration. The MCP process inherits the server environment;
set `GEN_AGENT_SERVER_PROVIDERS`, `GEN_AGENT_SERVER_CWD`, or
`GEN_AGENT_SERVER_CONFIG` for the projects and routes you want it to host.

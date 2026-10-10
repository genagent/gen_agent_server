# gen_agent_server

A runnable OTP application for using Claude and Codex through one GenAgent
entry point. It uses the published GenAgent, Ensemble, and CLI backend packages.
The default Echo backend needs no login and makes the application easy to
smoke-test. This is an early dogfooding host, not a durable job service.

## Run locally

```sh
mix deps.get
mix test
mix gen_agent_server agents
mix gen_agent_server ask echo "hello"
```

To use both locally authenticated CLI backends against a project:

```sh
GEN_AGENT_SERVER_PROVIDERS=claude,codex \
GEN_AGENT_SERVER_CWD=/path/to/project \
iex -S mix
```

```elixir
iex> GenAgentServer.agents()
{:ok, ["claude", "codex"]}
iex> GenAgentServer.ask("claude", "Summarize this project")
iex> GenAgentServer.ask("codex", "Find the test entry points")
iex> {:ok, id} = GenAgentServer.invoke("codex", "Find the test entry points")
iex> GenAgentServer.result(id)
```

The Claude backend uses plan permission mode. Codex uses a read-only sandbox
with approvals disabled and ignores the host user's Codex configuration by
default. Both keep their native project instructions and separate provider
sessions. `mix gen_agent_server ask PROVIDER PROMPT`
starts a fresh application for a single request; use IEx for a persistent
multi-turn session.

## Multiple projects in one server

Set `GEN_AGENT_SERVER_CONFIG` to a JSON file with named project profiles. Each
profile has its own working directory, backend sessions, and invocation result
store. Paths in `cwd` are relative to the JSON file; absolute paths also work.

```json
{
  "profiles": [
    {"name": "home", "cwd": "/path/to/home/project", "providers": ["claude", "codex"]},
    {"name": "work", "cwd": "/path/to/work/project", "providers": ["codex"],
     "codex_user_config": "inherit"}
  ]
}
```

```sh
MIX_ENV=prod mix release
GEN_AGENT_SERVER_CONFIG=/path/to/projects.json \
RELEASE_NODE=gen_agent_server_dogfood \
_build/prod/rel/gen_agent_server/bin/gen_agent_server start
```

### Provider child environment

A release leaks its boot environment (`RELEASE_*`, `BINDIR`, `ROOTDIR`, and
release `bin`/`erts-*/bin` `PATH` entries) into every child process. Project
tools spawned by Claude or Codex, such as a project's own `mix`, then fail
looking for the release's `start.boot`. The server never changes its own
environment; instead every Claude and Codex agent gets a child `:env` from
`GenAgentServer.ChildEnv` that unsets those variables and removes only the
exact release runtime directories from `PATH`. Shared MCP bearer configuration
(`GEN_AGENT_SERVER_SHARED_MCP_*`) is also forced unset in provider children.
Provider credentials and other inherited variables pass through untouched;
their inherited values are not copied into options or logged. This applies to
startup agents, profiles, dynamic routes, patterns, and direct
`start_instance/3` tuples.

Operators can extend the child environment with the trusted
`:provider_overrides` application setting, for example
`config :gen_agent_server, provider_overrides: %{"codex" => [env: %{"PATH" =>
"/opt/tools/bin:/usr/bin", "NO_COLOR" => "1", "TMPDIR" => false}]}`. A string
sets a variable, `false` unsets it, and a `PATH` override replaces the
inherited one. Cleanup runs after overrides, so release boot names stay unset
and release directories are stripped even from an override `PATH`. No client
operation or MCP schema accepts `env`.

The backend streaming launch paths use `false` for Port unsets. This does not
change standalone wrapper one-shot commands: ClaudeWrapper's System.cmd runner
requires `nil` for unsets. Optional Forcola runners are not enabled or validated
by this server. Non-CLI backends and custom raw `strategy_opts` are passed
through unchanged; typed patterns use the provider configuration above.

In another terminal, set the same node name before issuing remote commands:

```sh
export RELEASE_NODE=gen_agent_server_dogfood
mix gen_agent_server.remote instances
mix gen_agent_server.remote --instance home agents
mix gen_agent_server.remote --instance home invoke codex "Find a small issue worth fixing"
mix gen_agent_server.remote --instance home result INVOCATION_ID
```

Remote control and read commands have a 30-second RPC wait limit; synchronous
`ask` has a one-hour limit. Set `GEN_AGENT_SERVER_RPC_TIMEOUT_MS` and
`GEN_AGENT_SERVER_ASK_RPC_TIMEOUT_MS` to positive millisecond values to change
them. A timed-out RPC process is terminated. For work that may outlast a
synchronous `ask`, use `invoke` and check `result` later; the invocation keeps
running in the server after the short `invoke` RPC returns its ID.

The default `server/default` instance remains available and uses
`GEN_AGENT_SERVER_PROVIDERS` and `GEN_AGENT_SERVER_CWD`. Profile names must be
unique and cannot contain `/` or control characters. A missing directory,
unknown provider, or duplicate name fails startup. Profiles currently use the
same read-only Claude/Codex settings as the default. A profile can opt in to
edits with
`"codex_sandbox": "workspace_write"` and/or
`"claude_permission_mode": "accept_edits"`. Codex then uses its workspace
write sandbox with approvals disabled; Claude uses its CLI's accept-edits
permission mode. These are provider controls, not a server-enforced file
allowlist. Use a separate worktree for coding tasks and review changes before
merging. The server rejects broader Codex sandbox modes and Claude's bypass
mode from profile configuration.

`"codex_user_config"` accepts `"ignore"` (the default) or `"inherit"`.
Ignoring passes the Codex CLI's `--ignore-user-config` option on fresh and
resumed turns, avoiding host-specific MCP servers, model defaults, and other
settings in the operator's user configuration. `"inherit"` leaves those
settings available to the CLI. The installed Codex CLI still handles its own
authentication; this setting does not provide credentials. Pattern specs also
accept `"codex_user_config"` with the same choices.

`"codex_response_text"` accepts `"all_messages"` (the default) or
`"final_message"`. The default joins every completed Codex agent message with
a blank line, preserving existing behavior. `"final_message"` makes the
completed result text only the last agent message, which is useful when Codex
emits commentary before a final structured answer. Text events are still
preserved. Static profiles and pattern specs accept the same choices.

Until this adapter option is released, this server pins the core and Codex
integration to immutable source revision
`b251a1321242edea1c895f76e0a16d38c357dc53` in `mix.exs` and `mix.lock`.
No published adapter version provides this option yet; replacing the source
pin requires a release that includes it.

## Optional scheduled turns

The same JSON file may define Quantum jobs. No jobs run unless configured;
Oban, a database, and workers are not required. A job names an instance and
agent, a cron expression or alias such as `@hourly` or `@daily`, and exactly
one `prompt` or `prompt_file`. A prompt file is read for each run, so editing
it changes the next task without restarting the server.

```json
{
  "profiles": [
    {"name": "home", "cwd": "/path/to/project", "providers": ["codex"]}
  ],
  "jobs": [
    {"name": "daily-review", "instance": "home", "agent": "codex",
     "schedule": "@daily", "prompt_file": "daily-review.md", "overlap": false}
  ]
}
```

```sh
mix gen_agent_server.remote jobs
mix gen_agent_server.remote run-job daily-review
mix gen_agent_server.remote job daily-review
mix gen_agent_server.remote --instance home result INVOCATION_ID
```

`run-job` queues one immediate run, and `job NAME` returns its latest admitted
invocation ID or `never run`. Poll `job NAME` after queuing if the ID is not
available yet. The default `overlap: false` skips another run while the first
agent turn is active; set `overlap: true` only when parallel turns are wanted.
Jobs run on the local node. Scheduler restarts do not replay missed runs,
and results remain subject to the instance's bounded, process-local retention.
Invalid cron expressions fail configuration loading with the job name and file
path.
An admission rejection or prompt-file read failure has no invocation ID;
inspect Quantum job telemetry for that run. Admission rejections also emit
the server's usual rejection event with `source: :scheduler`. Turns with a known
invocation ID can be cancelled through the Elixir API below. Start with read-only
jobs and review their results.

`invoke/2` returns an instance-scoped ID after Ensemble admits the turn. `result/1` returns
`{:ok, :pending}`, `{:ok, :completed, response}`, or
`{:ok, :failed, reason}`. Completed results can be read repeatedly, including
after the caller exits. The default instance admits at most 16 in-flight
turns and retains up to 100 completions; additional admissions
return `{:error, :busy}` while all in-flight slots remain occupied. A new
admission checks for completed turns before applying this limit. An `ask/3` timeout only ends
the wait: the invocation keeps running and its result remains available through
its ID if the caller used `invoke/2`.

The Elixir API also supports cancellation and optional terminal delivery:

```elixir
{:ok, id} = GenAgentServer.invoke("review", "codex", "Review this module",
  recipient: self(), source: :api)
GenAgentServer.cancel("review", id)
# {:ok, :cancelled} or {:ok, :cancelled_unconfirmed} when cancellation wins
# receive {:gen_agent_server, :completion, metadata, terminal_result}
```

Cancellation collects existing completions first. A retained terminal ID returns
`{:error, :already_finished}`; unknown, evicted, wrong-instance or previous-generation
IDs return `{:error, :not_found}`, and a missing instance returns
`{:error, :instance_not_found}`. Older Ensemble releases without `cancel/2` and
custom strategies without cancellation support return `{:error, :unsupported}`
and leave work pending. Results retain the existing shape: cancellation is
`{:ok, :failed, :cancelled}` and reads remain repeatable until eviction.

Recipient must be a PID or nil; invalid values are rejected before admission.
Recipient options are consumed by the server and never forwarded to Ensemble or
backends. For every observed terminal success, error or cancellation, the owner
attempts one send before result eviction. Metadata includes `instance`, `agent`,
`invocation_id`, `ensemble_token` and `source`; cancellation includes
`cancellation_ack`. Cancellation observed without an owner acknowledgement uses
`:cancelled_unconfirmed`. The message carries the full retained result, even if
that result is subsequently evicted in the same batch. There is no durable
delivery, dead-recipient receipt or instance-shutdown notification guarantee.

Cancellation is synchronous and can block the invocation owner for potentially
unbounded time, delaying invoke/result/cancel calls. Its acknowledgement covers
request cancellation, not external provider process settlement. Finalization
releases raw admission capacity while unrelated work continues. The owner remains
the sole Ensemble inbox consumer; do not drain its managed session directly.

An embedding application can run independent instances with distinct agent
specs and result stores:

```elixir
{:ok, _pid} = GenAgentServer.start_instance("review", agents,
  max_in_flight: 4, max_results: 50)
{:ok, id} = GenAgentServer.invoke("review", "codex", "Review this module")
GenAgentServer.result("review", id)
GenAgentServer.ask_instance("review", "codex", "Summarize the finding")
GenAgentServer.stop_instance("review")
```

Each `agents` entry has the same `{name, callback_module, backend_options}`
shape as `config/runtime.exs`. Result IDs are meaningful only within their
instance. All results and provider sessions remain process-local and volatile.

Pattern instances use one external route while Ensemble owns their internal
stages or workers. For example, a Pipeline can use the same invocation IDs
and result store as a Switchboard instance:

```elixir
{:ok, _pid} = GenAgentServer.start_pattern_instance(
  "review-pipeline", "review", GenAgentEnsemble.Strategies.Pipeline,
  stages: [
    {"draft", GenAgentEnsemble.Agents.Simple, backend: GenAgentEnsemble.Backends.Echo},
    {"revise", GenAgentEnsemble.Agents.Simple, backend: GenAgentEnsemble.Backends.Echo}
  ]
)
{:ok, id} = GenAgentServer.invoke("review-pipeline", "review", "a short note")
GenAgentServer.result("review-pipeline", id)
```

`agents("review-pipeline")` lists the external `review` route, while
`status("review-pipeline")` shows both that route and Ensemble's internal
agents. The instance is created at runtime and disappears on restart; an
embedding application can start it again during its own startup. The JSON
profile format currently creates Switchboard instances only.

To start an OTP release:

```sh
MIX_ENV=prod mix release
RELEASE_NODE=gen_agent_server_dogfood \
_build/prod/rel/gen_agent_server/bin/gen_agent_server start
```

From another terminal, use the same `RELEASE_NODE` with the local remote
command. It passes the prompt as data, so quotes and newlines do not need to
be embedded in an Elixir expression:

```sh
RELEASE_NODE=gen_agent_server_dogfood \
mix gen_agent_server.remote ask echo "hello"
```

Use `mix gen_agent_server.remote invoke echo "hello"` and then
`mix gen_agent_server.remote result ID` to submit and inspect a turn across
separate shell commands. The local `mix gen_agent_server` task starts a fresh
VM, so its `invoke` and `result` commands are intentionally unavailable.
Both CLI tasks preserve UTF-8 output when piped. Expected request errors exit
non-zero with a single-line message that names the searched instance.
For a turn with multiple completed assistant messages, the CLI displays the
final message. `GenAgent.Response.text` still contains the assembled text of
the full turn, including earlier progress messages. Elixir API callers can
read the original response and its retained events with `GenAgentServer.ask/3`
or `GenAgentServer.result/2`; check `Response.event_coverage` before treating
the retained event list as complete.

To run an Ensemble pattern from a JSON spec, use `gen_agent_server.run`. The
included Echo specs are safe to try without a CLI provider:

```sh
mix gen_agent_server.run examples/specs/echo/pool.json \
  --prompt "Review one file" --prompt "Review another" --output report.json
```

`mix gen_agent_server.ops` lists the typed operations available to scripts and
the MCP adapter. `--remote` runs an operation in the release above, where
invocation results persist across commands. Set `MIX_QUIET=1` when parsing
stdout so a first-time Mix compile does not prefix the JSON with build notices:

```sh
MIX_QUIET=1 mix gen_agent_server.ops patterns
MIX_QUIET=1 mix gen_agent_server.ops invoke --agent echo --prompt "hello" --remote
MIX_QUIET=1 mix gen_agent_server.ops result --id INVOCATION_ID --remote
MIX_QUIET=1 mix gen_agent_server.ops run_pattern \
  --spec @examples/specs/echo/pool.json --prompts "Check a claim" --remote
```

Set `GEN_AGENT_SERVER_RELEASE_BIN` if the release binary lives elsewhere.
The release's `rpc` command remains available for direct Elixir calls.

## Shared local MCP (opt-in HTTP)

The running release can expose seven scoped tools to independent local clients
at an authenticated `http://127.0.0.1:<port>/mcp` endpoint. Only explicitly
allowed startup instances are reachable; clients cannot create instances or
select directories through this surface. See [startup, security, and volatile
semantics](docs/shared-mcp.md). The existing stdio catalogue still has 17 tools.

## MCP (stdio)

`GenAgentServer.MCP` serves a local stdio MCP server for Claude, Codex, or any
MCP client. It exposes seventeen tools, each backed by the operation of the same name
in `GenAgentServer.Ops`: `instances`, `agents`, `status`, `invoke`, `result`,
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
`effort`, `cwd`, and the access options `claude_permission_mode` (`read_only` by
default for dynamic routes, `plan`, or `accept_edits`), `codex_sandbox` (`read_only` by default, or
`workspace_write`), and `codex_user_config` (`ignore` by default, or `inherit`).
Codex routes also accept `codex_response_text` (`all_messages` by default, or
`final_message`). The default joins every completed agent message; the opt-in
uses only the last completed agent message for the result text. Edit modes,
config inheritance, and final-message selection are explicit per-route
opt-ins. `effort` is
`low`, `medium`, `high`, `xhigh`, or `max` for Claude, and `low`, `medium`, or
`high` for Codex, where it is sent as the fixed `model_reasoning_effort` config
override on both fresh and resumed turns. `echo` accepts only `name` and
`provider`. `cwd` must be an absolute existing directory; a top-level `cwd` is
the default for routes. Models are checked for shape only (up to 128 characters
of letters, digits, `.`, `_`, `:`, `/`, `@`, `[`, `]`, `-`, not starting with
`-`); the provider CLI decides whether it exists for the account. Up to 16
routes, `max_in_flight` up to 64, and `max_results` up to 1000.

For dynamic Claude routes, `read_only` uses the CLI's `dontAsk` mode with only
Read, Grep, and Glob tools available. It honored the selected Haiku model in
a live MCP turn. `plan` remains available, but Claude CLI 2.1.284 ignored an
explicit `--model haiku` and used Sonnet in a live plan-mode turn. Static
startup profiles keep their existing plan-mode default. Claude's CLI permission
modes and tool list are not a filesystem sandbox; use a separate worktree for
untrusted tasks.

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

### Existing Claude Desktop Code peers (experimental)

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

## Current contract

The default instance and any additional instances each own a named Ensemble
Switchboard and bounded result store. If one instance stops, its agents,
provider sessions, IDs, and results disappear. The default instance stops the
application if it fails rather than silently restarting with a fresh session.
An `ask` timeout or caller exit does not establish that an underlying provider
process stopped; GenAgent's turn watchdog bounds active work. There is no
durable admission, automatic retry, or cross-node result store yet.

The app has repeatable result reads for multiple clients. The stdio MCP
surface exposes only submit, wait, and read operations. Individual turn
cancellation remains to be defined in Ensemble before it is exposed over MCP or
used for broader unattended orchestration.

## Telemetry

The server emits `[:gen_agent_server, :invocation, :start | :stop | :error]`
for admitted turns, `[:gen_agent_server, :admission, :rejected]` for requests
that never received an ID, and `[:gen_agent_server, :wait, :timeout]` when a
synchronous caller stops waiting for a turn that may still be running.
Terminal invocation events have `duration_ms`; start and rejection events
have `system_time` in the VM native unit. The module
`GenAgentServer.Telemetry` documents the metadata contract.

Invocation events carry `instance`, `agent`, `invocation_id`,
`ensemble_token`, and `source` (`:api`, `:local_cli`, `:remote_cli`,
`:scheduler`, or `:mcp`). They never contain prompts, responses, provider
state, or raw errors. Use IDs and names to correlate a trace, not as metric
labels. Repeated `result` reads do not emit another terminal event.

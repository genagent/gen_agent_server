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
the server's usual rejection event with `source: :scheduler`. Individual
scheduled turns cannot yet be cancelled; GenAgent's turn watchdog bounds
active work. Start with read-only jobs and review their results.

`invoke/2` returns an instance-scoped ID after Ensemble admits the turn. `result/1` returns
`{:ok, :pending}`, `{:ok, :completed, response}`, or
`{:ok, :failed, reason}`. Completed results can be read repeatedly, including
after the caller exits. The default instance admits at most 16 in-flight
turns and retains up to 100 completions; additional admissions
return `{:error, :busy}` while all in-flight slots remain occupied. A new
admission checks for completed turns before applying this limit. An `ask/3` timeout only ends
the wait: the invocation keeps running and its result remains available through
its ID if the caller used `invoke/2`.

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

## MCP (stdio)

`GenAgentServer.MCP` serves a local stdio MCP server for Claude, Codex, or any
MCP client. It exposes six tools, each backed by the operation of the same name
in `GenAgentServer.Ops`: `instances`, `agents`, `status`, `invoke`, `result`,
and `ask`. Nothing else is reachable, including `run_pattern`, `stop_instance`,
jobs, and configuration. `invoke` and `ask` record telemetry source `:mcp`.

The MCP process starts its own application, with its own instances and result
store. Invocation IDs and results last for that MCP session and are not shared
with a separately running release or `mix gen_agent_server.remote`. Providers
come from the same environment variables as the rest of the server
(`GEN_AGENT_SERVER_PROVIDERS`, `GEN_AGENT_SERVER_CWD`, `GEN_AGENT_SERVER_CONFIG`);
the default is the model-free `echo` provider.

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
```

`invoke` and `ask` still request approval in this example because they start
provider work. In non-interactive `codex exec` runs with approvals disabled,
those calls fail unless the operator explicitly allows the specific tools in
that run's configuration. The MCP process inherits the server environment;
set `GEN_AGENT_SERVER_PROVIDERS`, `GEN_AGENT_SERVER_CWD`, or
`GEN_AGENT_SERVER_CONFIG` for the projects and routes you want it to host.

A session-to-session mailbox, HTTP transport, and broader control operations
are follow-on work, as is a dashboard.

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

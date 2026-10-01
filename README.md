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

The Claude backend uses plan permission mode and Codex uses a read-only
sandbox with approvals disabled. Both keep their native project instructions
and separate provider sessions. `mix gen_agent_server ask PROVIDER PROMPT`
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
    {"name": "work", "cwd": "/path/to/work/project", "providers": ["codex"]}
  ]
}
```

```sh
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

The default `server/default` instance remains available and uses
`GEN_AGENT_SERVER_PROVIDERS` and `GEN_AGENT_SERVER_CWD`. Profile names must be
unique and cannot contain `/`. A missing directory, unknown provider, or
duplicate name fails startup. Profiles currently use the same read-only
Claude/Codex settings as the default. A profile can opt in to edits with
`"codex_sandbox": "workspace_write"` and/or
`"claude_permission_mode": "accept_edits"`. Codex then uses its workspace
write sandbox with approvals disabled; Claude uses its CLI's accept-edits
permission mode. These are provider controls, not a server-enforced file
allowlist. Use a separate worktree for coding tasks and review changes before
merging. The server rejects broader Codex sandbox modes and Claude's bypass
mode from profile configuration.

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

Set `GEN_AGENT_SERVER_RELEASE_BIN` if the release binary lives elsewhere.
The release's `rpc` command remains available for direct Elixir calls.

A network API, MCP adapter, and dashboard are follow-on layers.

The [dogfooding log](docs/dogfooding.md) records bounded real tasks, observed
issues, and the planned progression through Ensemble patterns.

For a local, model-free look at Ensemble's Pipeline and Supervisor patterns,
run `mix run examples/ensemble_patterns.exs`. The example checks stage
handoff, two-worker fan-out, and worker cleanup inside the same OTP
application. It uses Ensemble directly; server-managed pattern invocations
and result IDs are a separate integration step.

## Current contract

The default instance and any additional instances each own a named Ensemble
Switchboard and bounded result store. If one instance stops, its agents,
provider sessions, IDs, and results disappear. The default instance stops the
application if it fails rather than silently restarting with a fresh session.
An `ask` timeout or caller exit does not establish that an underlying provider
process stopped; GenAgent's turn watchdog bounds active work. There is no
durable admission, automatic retry, or cross-node result store yet.

The app now has repeatable result reads for multiple clients. Individual
turn cancellation remains to be defined in Ensemble before this API is
exposed over MCP or used for broader unattended orchestration.

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

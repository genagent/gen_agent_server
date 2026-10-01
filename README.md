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

## Current contract

The default instance and any additional instances each own a named Ensemble
Switchboard and bounded result store. If one instance stops, its agents,
provider sessions, IDs, and results disappear. The default instance stops the
application if it fails rather than silently restarting with a fresh session.
An `ask` timeout or caller exit does not establish that an underlying provider
process stopped; GenAgent's turn watchdog bounds active work. There is no
durable admission, automatic retry, or cross-node result store yet.

The app now has repeatable result reads for multiple clients. The next slice
should add invocation lifecycle telemetry and explicit cancellation before
exposing this API over MCP or enabling unattended scheduling.

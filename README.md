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
```

The Claude backend uses plan permission mode and Codex uses a read-only
sandbox with approvals disabled. Both keep their native project instructions
and separate provider sessions. `mix gen_agent_server ask PROVIDER PROMPT`
starts a fresh application for a single request; use IEx for a persistent
multi-turn session.

To start an OTP release:

```sh
MIX_ENV=prod mix release
RELEASE_NODE=gen_agent_server_dogfood \
_build/prod/rel/gen_agent_server/bin/gen_agent_server start
```

From another terminal, use the same `RELEASE_NODE` with the release's `rpc`
command, for example:

```sh
RELEASE_NODE=gen_agent_server_dogfood \
_build/prod/rel/gen_agent_server/bin/gen_agent_server rpc \
  'GenAgentServer.CLI.main(["ask", "echo", "hello"])'
```

A network API, MCP adapter, and dashboard are follow-on layers.

## Current contract

The server runs one named Ensemble Switchboard session. Agents, provider
sessions, and results live in BEAM process memory and are lost on restart.
The application stops if its Switchboard process dies, rather than silently
replacing it with a fresh session under the same name.
An `ask` timeout does not establish that the underlying provider process
stopped. By default `ask` waits for a terminal result; GenAgent's turn
watchdog bounds active work. If the caller exits, its result is not retained
for a later lookup. The CLI offers synchronous `ask`; it does not expose Ensemble's
consuming `poll` and `inbox` as shared result reads. There is no durable
admission, automatic retry, or multi-client coordination yet.

The next app-host slice should make instances independently supervisable,
give invocations scoped identities, and retain bounded results for repeatable
reads. That contract should be tested before exposing it over MCP or adding
an Oban-backed mode.

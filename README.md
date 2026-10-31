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

## Retained invocation summaries (issue #75, first increment)

```elixir
{:ok, summaries} = GenAgentServer.invocations("review", limit: 50)
```

The same read is available as Ops `invocations` (and the stdio MCP tool):

```sh
MIX_QUIET=1 mix gen_agent_server.ops invocations --instance review --limit 50 --remote
```

Instance is required; limit defaults to 50 and accepts integers from 1 to 200.
Entries are ordered by newest admission, using a stable sequence even when
wallclock timestamps tie. Fields are `id`, `route`, `source`, `status`,
`admitted_at_unix_ms`, `completed_at_unix_ms`, `duration_ms`, and `error_category`.
Statuses are pending, completed, failed, or cancelled. Pending completion time
and duration are nil; terminal duration uses monotonic elapsed time and timestamps
use Unix milliseconds. Error categories are limited to timeout, task_crashed,
backend_error, and cancelled (nil for pending/success). No prompt, response,
raw error reason, recipient, or backend configuration is included.
Terminal timestamps and durations reflect the owner's first observation of
completion, rather than the provider's finish time.

Reads collect current completions from the invocation owner and are repeatable
while entries remain retained. Limit bounds the returned list; existing
`max_in_flight` and `max_results` bound storage. Eviction, instance shutdown, and
restart discard corresponding summaries. Unknown/stopped instances return
`instance_not_found`; a recreated instance begins empty. The Elixir API returns
`invalid_limit` for invalid limits; Ops also validates argument types.
An opt-in, read-only web observer for one running release, its allowlisted
instances and these summaries is in [examples/operator_view](examples/operator_view/README.md).
It is a separate Mix project: the server application and release gain no
Phoenix dependency and open no listener for it. Broader #75 work remains open.

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

The server uses published Hex packages: core `~> 0.8.0`, Ensemble `~> 0.7.0`,
Claude adapter `~> 0.3.0`, and Codex adapter `~> 0.6.0`. The Codex adapter
includes `response_text`; no Git dependency pins or core override are needed.
Each owned Ensemble retains at least `max_in_flight` unread completions until
the invocation owner collects them. The server's `max_results` separately
bounds retained results after collection.

## Invocations, results, and cancellation

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
`{:error, :instance_not_found}`. Custom strategies without cancellation support return `{:error, :unsupported}`
and leave work pending. Results retain the existing shape: cancellation is
`{:ok, :failed, :cancelled}` and reads remain repeatable until eviction.

The canonical `cancel` operation requires both a nonempty exact `instance` and
`id`; it never selects the default instance or retries. All adapters return
`instance`, `id`, and `status` (`cancelled` or `cancelled_unconfirmed`).
Errors retain `not_found`, `already_finished`, `instance_not_found`, and
`unsupported`. Retained results still report `failed` with error code `cancelled`.
A lost acknowledgement is uncertain: read `result` with the same pair instead
of automatically retrying. Acknowledgement does not prove provider cleanup.

```sh
mix gen_agent_server.ops cancel --instance review --id "$ID" --remote
mix gen_agent_server.remote --instance review cancel "$ID"
```

Both stdio and shared MCP accept `cancel` with `{"instance":"review","id":"..."}`.
Shared MCP requires its bearer token and an allowed instance for cancellation.

Recipient must be a PID or nil; invalid values are rejected before admission.
Recipient options are consumed by the server and never forwarded to Ensemble or
backends. For every observed terminal success, error or cancellation, the owner
attempts one send before result eviction. Metadata includes `instance`, `agent`,
`invocation_id`, `ensemble_token` and `source`; cancellation includes
`cancellation_ack`. Cancellation observed without an owner acknowledgement uses
`:cancelled_unconfirmed`. The message carries the full retained result, even if
that result is subsequently evicted in the same batch. There is no durable
delivery, dead-recipient receipt or instance-shutdown notification guarantee.

Cancellation is synchronous for the invocation owner; a slow child acknowledgement
can delay its invoke/result/cancel calls. Ensemble 0.7.4 keeps its control loop
responsive during child admission and cancellation (dependency #221). The server
requires Ensemble >=0.7.4 and its compatible core >=0.10.0 and adapters
Claude >=0.3.2 / Codex >=0.6.2. Its acknowledgement covers
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

Configured route descriptions also include `review_read_only_explicit`: true
only when the Claude/Codex route config explicitly supplied its `read_only` mode,
false for omitted modes and Echo. It describes configuration provenance for the
optional controller's review policy; it is not a backend option. Existing
provider defaults still apply to ordinary invocations.

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

## Extensions

Everything above driving agents is an optional extension under
[`extensions/`](extensions). An extension is a separate Mix project; a host
lists the ones it wants:

```elixir
config :gen_agent_server, extensions: [GenAgentServer.MCP]
```

With none listed, the server starts only its instances and the base `Ops`
catalogue. See `GenAgentServer.Extension` for the callbacks.

| Extension | What it adds |
| --- | --- |
| [mcp](extensions/mcp/README.md) | Stdio MCP server and opt-in shared HTTP listener over `Ops` |
| [public_source](extensions/public_source/README.md) | `public_*` operations: anonymous reads of public GitHub source and issues |
| [selection](extensions/selection/README.md) | Pure route suggestions (library) |
| [control](extensions/control/README.md) | Caller-started controller and evidence ledger (library) |
| [patterns](extensions/patterns/README.md) | `run_pattern` and `patterns` operations, `mix gen_agent_server.run` |
| [schedule](extensions/schedule/README.md) | Quantum calendar jobs from the configuration file |

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

The app has repeatable result reads for multiple clients. Stdio and shared local
MCP expose explicit invocation cancellation with the exact instance and ID.
Cancellation acknowledgement does not establish provider process cleanup.

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

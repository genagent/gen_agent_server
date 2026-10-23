# Operator view (read-only, opt-in example)

A separate Mix project with one Phoenix LiveView page that observes one
already running `gen_agent_server` release: which allowlisted instances are
running, the selected instance's routes and runtime status, and up to 50 of its
retained, content-free invocation summaries. It is the first observation slice
of [#75](https://github.com/genagent/gen_agent_server/issues/75).

It only reads. It has no submit, cancel, job, workflow, queue or result-content
controls, and it never starts provider work, retries work or starts instances.
Existing clients (the remote CLI, Ops, MCP) keep running agents.

The server application and release are unchanged: they do not depend on
Phoenix and open no listener for this page. Phoenix, LiveView and Bandit are
dependencies of this example only, and this VM never starts the server
application (`gen_agent_server` is a `runtime: false` path dependency used
only for its existing `GenAgentServer.Ops.Remote` reader).

## Run

Start the server release as usual, in one terminal:

```sh
MIX_ENV=prod mix release
RELEASE_NODE=gen_agent_server_dogfood \
_build/prod/rel/gen_agent_server/bin/gen_agent_server start
```

Then start the observer from this directory, in another:

```sh
cd examples/operator_view
mix deps.get
export OPERATOR_VIEW_TOKEN="$(openssl rand -hex 24)"
echo "$OPERATOR_VIEW_TOKEN"
RELEASE_NODE=gen_agent_server_dogfood \
OPERATOR_VIEW_RELEASE_BIN=/abs/path/to/gen_agent_server/_build/prod/rel/gen_agent_server/bin/gen_agent_server \
OPERATOR_VIEW_INSTANCES=server/default,review \
mix run --no-halt
```

Open <http://127.0.0.1:4075/login> and enter the token.

Dependencies and build output for this project live under the server's
ignored `_build/operator_view` directory (see `mix.exs`), so the server's
formatter inputs (`examples/**/*.{ex,exs}`) never reach fetched dependency
sources.

| Variable | Required | Meaning |
| --- | --- | --- |
| `OPERATOR_VIEW_TOKEN` | yes | Operator login token, at least 24 bytes |
| `OPERATOR_VIEW_INSTANCES` | yes | Comma-separated allowlist, 1 to 16 instance names |
| `OPERATOR_VIEW_RELEASE_BIN` | yes | Absolute path to the release executable |
| `OPERATOR_VIEW_PORT` | no | Loopback port, default 4075 |
| `RELEASE_NODE` | as for the release | Node name of the running release |
| `RELEASE_COOKIE` | no | Only if the release does not use its own cookie file |

## Boundary

- One trusted local operator. The endpoint binds `127.0.0.1` only and refuses
  to start with any other address. HTTP requests must name `127.0.0.1` or
  `localhost` as their host and come from `127.0.0.1`. Phoenix dispatches the
  LiveView socket upgrade before those checks, so the socket instead accepts
  only those exact origins, and it reads the session only when the upgrade
  carries the page's CSRF token.
- The login page compares the token in constant time. A successful login
  stores a marker derived from the token in a signed, encrypted session
  cookie. HTTP routes and every LiveView mount and reconnect check it.
  Changing the token or restarting the observer (a fresh signing key per
  start) ends existing sessions. Normal Phoenix CSRF protection applies.
- Reads use the release's trusted local RPC (`bin/gen_agent_server rpc`),
  the same path as `mix gen_agent_server.ops --remote`. The observer process
  therefore holds the release's full RPC authority. The page narrows what the
  browser can reach: `OperatorView.Reader` sends only the `instances`,
  `describe_instance`, `status` and `invocations` operations, always with an
  explicit allowlisted instance and `limit: 50`. Browser input can only pick
  an allowlisted instance and ask for a refresh; it never supplies an operation
  name, executable, node, cookie, path or RPC expression. The allowlist is
  checked on mount and on every selection and refresh. Other events are
  ignored.
- This does not use shared-MCP bearer authorization (shared MCP does not
  expose `invocations`), and it is not designed for remote or multi-user
  deployment.
- The token and release path never appear in HTML or URLs, and the `token`
  login parameter is filtered from request logs. Release errors are reduced to
  fixed categories (`release read timed out`, `release unavailable`,
  `unreadable release output`, `read failed`); release output and messages are
  not shown.

## What the page shows

- Allowlisted instances, each running, not running or unknown (when the
  instance list could not be read). Membership is checked against the whole
  instance list the release returns, however long. An allowlisted instance
  that is not running stays visible as unavailable.
- Routes and limits from `describe_instance`. Instances not created through
  `create_instance` report route names only, so their provider, model, effort
  and access columns read `unknown`. A setting the release reports as `null`
  reads `not set`. Route `cwd` is not shown.
- Runtime status: strategy, external routes, internal agents, and in-flight
  and pending counts when the status contains those fields. Other
  strategy-specific status fields are listed by name only. This is runtime
  state, not provider health.
- Up to 50 retained invocation summaries, newest admission first: ID, route,
  source, status, admission and completion times, duration and error category.
  Unrecognized statuses, sources or categories read `unknown`. These are the
  release's retained entries, not totals or durable history: eviction,
  instance stop and restart remove them, and an empty table after a restart
  means nothing is retained, not that earlier work completed. Terminal times
  are the invocation owner's observation, not the provider's finish time.

Each section shows its own read time, because sections are separate reads and
not one atomic snapshot.

## Refresh and reconnect

- The disconnected HTTP render reads nothing. Each connected mount, including
  a reconnect, a selection change and the Refresh button, reads a full
  snapshot (instance list, description, status, summaries) and replaces the
  page state with it. Nothing is rebuilt from telemetry and nothing is ever
  resubmitted.
- After each refresh the page polls status and summaries once every five
  seconds. At most one refresh worker runs per page; a Refresh while one is
  running is coalesced into one follow-up full refresh.
- Each read has a five-second RPC limit, and a refresh worker that does not
  finish within its deadline (by default four RPC limits plus one second) is
  stopped. A refresh stops at its first failed read.
- After a failed or stalled read the previous data stays visible labelled
  stale, and automatic polling pauses until the operator presses Refresh.
  There are no automatic retries against a failing release.
- A reply that belongs to a previously selected instance is discarded.
- Closing the page stops its timer and refresh worker. A timed-out RPC control
  VM is stopped by `Ops.Remote`; this bounds the page's wait, not provider
  execution or the release's own invocation owner.
- Each RPC runs in its own process, watched by a supervised guard that is not
  linked to the refresh worker. When the worker is stopped (page closed or
  deadline passed) during an RPC, the guard stops the RPC's operating-system
  process tree (TERM, then KILL after 100 ms, checking each process's start
  time) before discarding the RPC process, so no control VM outlives the page.

Each read starts a short-lived release control VM, so every open page adds two
RPCs every five seconds while polling, and four for each full refresh. Keep few
pages open.

## Tests

```sh
cd examples/operator_view
mix deps.get
mix test
```

The tests use no provider and no external network:

- a scripted stand-in transport for authentication and allowlist scope,
  refresh coalescing, polling, stalled and failed reads, stale data,
  unavailable instances, old-selection replies and page shutdown;
- authentication with CSRF enforcement switched back on for login and logout,
  a connected mount of an already rendered page whose session became invalid,
  and the LiveView socket on a loopback listener: rejected origins, joins
  without the page's CSRF token or session, and a reconnect after the token
  rotates;
- an allowlisted instance listed after more than 64 other instances;
- stand-in release executables for the real `Ops.Remote` RPC path (fixed
  expression, failure, bad output, timeout, missing executable), and checks
  that a stopped caller, a closed page and a refresh deadline each leave no
  RPC operating-system process behind;
- the real server application started inside the test VM with Echo and gated
  test backends, read through the release's own Ops envelope, for pending,
  completed, cancelled and failed summaries, two instances, eviction, instance
  restart, and reconnect without resubmission;
- a startup check that the observer starts only its own web tree and that the
  server's dependencies gain no Phoenix.

## Not included

These remain open follow-ups under #75 and related issues:

- cancel or submit controls (cancel waits on the separate Ops/CLI/MCP
  cancellation contract in #127);
- result content drill-down, jobs, telemetry event history, rejected
  admissions and caller wait timeouts, live streaming and persistence;
- exposing `invocations` over shared MCP, embedding the page in another
  Phoenix host, a published package, and `gen_agent_live` compatibility.

# Shared local MCP (first slice of #81)

The running release can host an opt-in Streamable HTTP endpoint at
`http://127.0.0.1:<port>/mcp`. Independent clients share its existing instance
owners, provider work and bounded volatile result stores. Stdio remains a
separate VM per client and retains all 17 tools. Shared HTTP exposes exactly
seven: `instances`, `agents`, `status`, `describe_instance`, `invoke`, `result`,
`ask`. The issue's original six-tool count is stale.

## Startup

Build with `MIX_ENV=prod mix release`. In the environment of the release:

```sh
export GEN_AGENT_SERVER_SHARED_MCP_ENABLED=true
export GEN_AGENT_SERVER_SHARED_MCP_PORT=4381
export GEN_AGENT_SERVER_SHARED_MCP_INSTANCES='["server/default"]'
# Load a strong, operator-managed secret; do not paste it into a command argument.
export GEN_AGENT_SERVER_SHARED_MCP_TOKEN="$(openssl rand -hex 32)"
_build/prod/rel/gen_agent_server/bin/gen_agent_server start
```

Persist the secret securely if clients need it after restart. The token must be
32..256 URL-safe ASCII characters (`A-Z`, `a-z`, digits, `_`, `-`). Configuration
stores only its SHA-256 digest. All `GEN_AGENT_SERVER_SHARED_MCP_*` variables
are forced unset in Claude/Codex provider children, including trusted env
overrides. Provider credentials still pass through normally.

The shared listener starts only in a packaged release. Mix tasks, tests, and
other short-lived local app starts ignore these variables so they do not seize
the release's port or create a second, ephemeral shared server.

`ENABLED` defaults to disabled in a release; only literal `true` enables it. A partial or
malformed configuration fails startup, including ancillary shared settings
while disabled, a port outside 1..65535, an empty/duplicate instance list, or a
name absent from the default instance and startup profiles. `INSTANCES` is a
JSON array of 1..64 distinct names, each 1..256 bytes. Profiles continue to use
the existing operator-owned `GEN_AGENT_SERVER_CONFIG` file. Runtime-created
instances cannot be added to shared scope through MCP. A bind failure fails
startup. There is no unauthenticated fallback or alternate bind address.

Configure each HTTP-capable MCP client with the URL and an `Authorization:
Bearer <token>` header on **every** request, including discovery, notifications,
and session termination. Prefer the client's secret/environment support over
literal credentials in project files. A stdio-only client cannot attach to this
listener; no relay is supplied. Using `bin/... eval GenAgentServer.MCP.serve()`
still starts a separate stdio VM, not an attachment to the running release.
The standalone stdio entry point suppresses the HTTP listener even if it inherits
valid shared settings, so it does not compete for the running release's port.

For Snodo 0.4.1, a client can connect using:

```elixir
{:ok, client} = Snodo.Client.connect({:http, "http://127.0.0.1:4381/mcp"},
  headers: [{"authorization", "Bearer " <> System.fetch_env!("MY_MCP_TOKEN")}])
Snodo.Client.call_tool(client, "instances", %{})
Snodo.Client.call_tool(client, "invoke", %{
  "instance" => "server/default", "agent" => "echo", "prompt" => "hello"
})
# Save the returned instance + id and supply both to result.
```

## Boundary and bounds

The listener binds only IPv4 `127.0.0.1`. The gate requires exactly one bearer
header and compares token digests in constant time. Host must be exactly
`127.0.0.1:<configured port>`; Origin may be absent or exactly
`http://127.0.0.1:<configured port>`. Other origins, `null`, duplicate headers,
`localhost`, alternate ports and other routes are refused before body reads.
Native non-browser clients normally omit Origin. Browser support is intentionally
limited: no CORS/preflight route, OAuth discovery or proxy mode is supplied.
Snodo also checks Host/Origin at HTTP adapter admission.

The endpoint accepts POST MCP messages. The gate also authenticates other
methods before Snodo refuses them. Malformed/oversize HTTP heads can be rejected
by the parser before credentials are examined, without executing MCP work.
There is no GET event stream, provider resume registry, mailbox, lifecycle,
peer, public-source, scheduler, arbitrary OTP operation/module or filesystem-path
selector. The shared server registers no resources or prompts. Tool schemas
advertise `additionalProperties: false`; Snodo's schema validator is advisory,
while operation callbacks enforce argument allowlists and `ask` validates its
own keys and timeout. Provider prompts still carry the authority of the operator's
preconfigured routes; select provider modes and working directories accordingly.

The single token grants one shared operator identity and the same configured
scope to every client; it supplies no per-client privacy or quota. Discovery
lists only allowed running instances. Every other tool requires an explicit
allowed instance. Snodo Authorization checks both catalogue discovery and direct
invocation, and callbacks recheck instance scope. Client request metadata cannot
supply trusted identity. Invocation telemetry retains source `:mcp`; individual
client attribution and token rotation without restart are deferred.

Fixed bounds: 32 connections, 8 executing requests, 16 queued requests, 8 KiB
headers, 64 KiB request bodies; head/body/read deadlines 2 s, gate deadline 1 s,
request deadline 10 s and drain deadline 1 s. Excess connections close; executor
overload returns 503. Existing instance in-flight/result limits and provider
watchdogs remain authoritative. This is an authenticated local service, not a
public multi-tenant deployment or a generic reverse-proxy target.

`ask` waits 1000 ms by default and accepts only 0..5000 ms. It returns
`instance`, `id`, and `status` even when still pending. Completed/failed replies
include the same pair. Use `invoke` then `result` for long work. Shared `ask`
has these semantics independently of the existing stdio `ask` behavior.

## Volatile work and failure

Admitted invocation work belongs to the existing instance and provider task,
not an HTTP connection. Disconnecting or timing out a client cancels only its
request worker/wait; it does not cancel provider work or erase results. A lost
submission response can leave admitted work whose ID the caller never received.
There is no submission idempotency key or invocation history tool in this slice:
do not blindly retry `invoke`/`ask` after an ambiguous disconnect.

Result reads are repeatable across clients until the instance's bounded store
evicts them. Release restart, instance stop or instance failure discards work
and results. IDs are opaque `inv-<random instance namespace>-<counter>` strings;
the namespace contains 192 random bits and changes for each instance lifetime,
including after a release restart. An old ID returns `not_found` in a restarted
instance, or `instance_not_found` if the instance is absent, and cannot practically
alias a new invocation. Pre-change `inv-2` IDs are also unknown. Do not parse
the counter or assume IDs survive restart.

The HTTP listener is a temporary worker in a separate temporary supervisor at
the end of the application tree. Listener/executor failure takes the HTTP
endpoint offline and preserves existing invocation state. It does not silently
restart the application or create empty result stores. An operator can restart
only the listener's supervision boundary in the running VM using the trusted
release RPC interface:

```sh
_build/prod/rel/gen_agent_server/bin/gen_agent_server rpc '
  config = Application.fetch_env!(:gen_agent_server, :shared_mcp)
  Supervisor.terminate_child(GenAgentServer.Supervisor, GenAgentServer.MCP.Shared)
  Supervisor.start_child(GenAgentServer.Supervisor, {GenAgentServer.MCP.Shared, config})
'
```

This preserves invocation owners; restarting the entire release loses them.
Normal instance failure behavior remains unchanged. No bearer token, raw token
config or child env secret value is emitted by this implementation's errors.

## Verification

```sh
mix test test/gen_agent_server_shared_mcp_test.exs test/gen_agent_server_mcp_test.exs test/gen_agent_server_child_env_test.exs
MIX_ENV=prod mix release
mix run examples/mcp_release_smoke.exs
mix run examples/shared_mcp_release_smoke.exs
```

The shared socket test checks two independent Snodo HTTP clients, a disconnect
during a blocked provider turn, and listener failure isolation. Deterministic
tests separately exercise the gate, Authorization, two independent HTTP request
contexts through Snodo's real adapter, bounded waits and instance recreation.
The packaged shared smoke starts one long-lived packaged VM, shares an Echo
result between clients, disconnects a client, then restarts the VM and verifies
the old ID stays unknown before and after new work. It is bounded and requires
loopback sockets. A real Claude/Codex MCP-client probe should use this same URL
and operator-managed token, only an allowed Echo route, a bounded timeout, and
compare the returned instance/ID/result from both clients.

See [the validation report](shared-mcp-validation.md) for the worker's sandbox
limitation and the completed acceptance results from the parent session.

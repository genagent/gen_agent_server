# #81 isolated-checkout handoff — 2026-10-09

Branch: `feat/shared-mcp-81`. Changes remain uncommitted. No push, PR, label
change, external message or GitHub write was performed. Snodo 0.4.1 was inspected
locally in `deps/snodo`, specifically its native listener, RequestGate,
Authorization/Component, runtime, executor and HTTP client implementations.
No dependencies or lockfile were changed.

The implementation is opt-in and disabled by default. The Tosi worker could not
validate HTTP because its sandbox prohibits loopback and Unix socket binds.
The parent session later completed socket tests, both packaged release smokes,
and real Claude and Codex CLI probes outside that sandbox; see the final
verification below. The worker's results remain here to document the exact
delegation limitation.

## Exact changed files

| File | Change |
| --- | --- |
| `README.md` | Shared HTTP entry point and child-secret handling links |
| `config/runtime.exs` | Parse opt-in shared MCP environment at release boot |
| `mix.exs` | Declare OTP crypto application explicitly |
| `lib/gen_agent_server/application.ex` | Validate configured scope; append isolated listener boundary |
| `lib/gen_agent_server/child_env.ex` | Force-unset shared MCP configuration in CLI provider children |
| `lib/gen_agent_server/invocations.ex` | Fresh random namespace per instance lifetime in opaque IDs |
| `lib/gen_agent_server/mcp.ex` | Standalone stdio startup suppresses inherited HTTP listener config |
| `lib/gen_agent_server/mcp/shared.ex` | Isolated temporary supervision, bounds, scoped dispatch and bounded ask |
| `lib/gen_agent_server/mcp/shared/config.ex` | Strict opt-in configuration; token digest; configured-instance validation |
| `lib/gen_agent_server/mcp/shared/gate.ex` | Bearer, exact Host/Origin and endpoint admission |
| `lib/gen_agent_server/mcp/shared/authorization.ex` | Tool discovery and direct-call identity/scope enforcement |
| `lib/gen_agent_server/mcp/shared/server.ex` | Separate seven-tool runtime with accurate shared instructions |
| `lib/gen_agent_server/mcp/shared/tools.ex` | Seven fixed tool callbacks; explicit instance and bounded ask schemas |
| `test/gen_agent_server_shared_mcp_test.exs` | Nine deterministic checks and one socket-level integration test |
| `test/gen_agent_server_mcp_test.exs` | Existing stdio wire test also inherits valid shared config, preserving all 17 tools |
| `test/gen_agent_server_child_env_test.exs` | Actual Claude/Codex Port runners prove shared token is absent |
| `examples/mcp_release_smoke.exs` | Additional packaged VM restart ID check |
| `examples/shared_mcp_release_smoke.exs` | Bounded packaged HTTP two-client, disconnect and restart smoke |
| `docs/shared-mcp.md` | Startup, client configuration, security, limits, failure recovery and volatile semantics |
| `docs/shared-mcp-validation.md` | This exact-file/command/result handoff and Tosi reproduction |

## Commands and decisive output

The local Elixir is 1.20.4. Mix's socket-based compilation lock must be disabled
for this isolated checkout; compilation was run sequentially. The environment
variable is a testing workaround, not a change to application security.

Initial attempt:

```sh
mix test test/gen_agent_server_mcp_test.exs test/gen_agent_server_child_env_test.exs
```

Exit 1:

```text
warning: failed to subscribe to Mix events using TCP, reason: :eperm
** (Mix) failed to acquire filesystem lock using TCP, reason: :eperm
```

After inspecting installed Mix's lock implementation:

```sh
MIX_OS_CONCURRENCY_LOCK=0 mix test test/gen_agent_server_mcp_test.exs test/gen_agent_server_child_env_test.exs
```

Exit 0: `Result: 26 passed`.

Focused shared check:

```sh
MIX_OS_CONCURRENCY_LOCK=0 mix test test/gen_agent_server_shared_mcp_test.exs --exclude shared_http
```

Final run exit 0: `Result: 9 passed, 1 excluded`. The excluded case is explicitly
tagged `:shared_http`, not silently skipped by automatic environment detection.
The nine passing tests cover strict/redacted configuration, the bearer and
Host/Origin gate, separate seven-tool discovery, unauthorized discovery/calls,
extra argument refusal, bounded ask returning a pollable ID, killed-waiter
provider survival, instance recreation rejecting old IDs, provider env cleanup,
and independent HTTP request contexts through Snodo's real adapter. Some tests
combine related checks.

Combined MCP/environment check:

```sh
MIX_OS_CONCURRENCY_LOCK=0 mix test test/gen_agent_server_shared_mcp_test.exs test/gen_agent_server_mcp_test.exs test/gen_agent_server_child_env_test.exs --exclude shared_http
```

Exit 0: `Result: 35 passed, 1 excluded`.

Final broader affected-code check:

```sh
MIX_OS_CONCURRENCY_LOCK=0 mix test test/gen_agent_server_test.exs test/gen_agent_server_ops_test.exs test/gen_agent_server_telemetry_test.exs test/gen_agent_server_lifecycle_test.exs test/gen_agent_server_dispatch_test.exs test/gen_agent_server_shared_mcp_test.exs test/gen_agent_server_mcp_test.exs test/gen_agent_server_child_env_test.exs --exclude shared_http
```

Exit 0: `Result: 80 passed, 1 excluded`. This final run includes the stdio startup
fix for inherited shared settings and the real runner token-removal checks.

Full-suite attempt:

```sh
MIX_OS_CONCURRENCY_LOCK=0 mix test --exclude shared_http
```

Exit 2:

```text
Result: 110/136 passed, 1 excluded
Failed: 26 tests
```

Nineteen failures are existing PeersTest setup attempts to bind local Unix
sockets returning `{:error, :eperm}`. Seven are existing CLI/OpsCLI tests whose
captured output includes the Mix TCP subscription warning: exact-line/UTF-8
comparisons fail, JSON decoding sees the `w` in `warning`, or a mock release RPC
envelope becomes invalid. No unrelated test or CLI behavior was changed to hide
these failures. This run preceded the final stdio inherited-config regression
check; the affected-code suite above was rerun after that change.

Packaged checks:

```sh
MIX_OS_CONCURRENCY_LOCK=0 MIX_ENV=prod mix release
MIX_OS_CONCURRENCY_LOCK=0 MIX_ENV=prod mix release --overwrite
MIX_OS_CONCURRENCY_LOCK=0 mix run examples/mcp_release_smoke.exs
```

All exit 0. Final decisive output:

```text
Release created at _build/prod/rel/gen_agent_server
MCP release smoke passed
MCP release restart ID smoke passed
```

The stdio smoke checks all 17 tools, legacy protocol discovery, resources,
Echo/lifecycle operations and repeatable reads. Its restart extension closes a
packaged stdio VM, starts a new packaged VM, checks the old ID is unknown, submits
new work, checks distinct namespaces and checks the old ID remains unknown.

Actual HTTP attempts:

```sh
MIX_OS_CONCURRENCY_LOCK=0 mix test test/gen_agent_server_shared_mcp_test.exs --only shared_http
MIX_OS_CONCURRENCY_LOCK=0 mix run examples/shared_mcp_release_smoke.exs
```

The first exits 2: `Result: 0/1 passed, 9 excluded`; its first
`:gen_tcp.listen(0, ip: {127, 0, 0, 1})` returns `{:error, :eperm}`. The smoke
exits 1 at the same initial bind. Neither reached network client execution.

Additional packaged startup probes used Python `subprocess.run` with a bounded
15-second timeout, a fake token supplied only through child environment, and:

```text
bin/gen_agent_server eval 'Application.ensure_all_started(:gen_agent_server) |> IO.inspect()'
```

With an unconfigured instance, the returned startup error contains
`INSTANCES must name only startup-configured instances`. With the configured
default instance, it reaches native listener startup and fails with `:eperm`.
Both outputs were checked for the raw fake token: absent. `eval` itself exits
0 because the expression prints the returned error; application startup fails.

Formatting of every changed Elixir file and `git diff --check` pass. Initial
dependency compilation emitted existing crontab/gen_stage warnings. Mix's
subscription warning remains visible under this sandbox even with its lock
disabled.

## Tradeoffs and remaining blockers

The first slice uses one operator token and one explicit instance allowlist for
all clients. No individual client attribution, per-client quota, dynamic scope,
token reload, durable store, resume/mailbox, public-source/peer/lifecycle surface
or arbitrary RPC is exposed. `ask` has a 5-second maximum wait and returns a
pending ID; `invoke`/`result` are preferred for long turns. Memory/result limits
and provider watchdogs remain owned by existing instances.

Listener failure leaves HTTP offline, with provider work/results retained.
Automatic restart is intentionally absent; docs give trusted RPC recovery of
only the listener boundary. Whole-release restart discards volatile state.
Opaque ID format changes for stdio/API too: 192 random namespace bits prevent
practical reuse after instance or VM restart. Submission response loss is
ambiguous; idempotent submission and invocation enumeration are deferred.

Remaining acceptance blockers are concrete:

1. Run the socket test in this checkout on a host permitting loopback binds
   to validate two independent HTTP clients, a real disconnect during admitted
   provider work, and listener failure during an in-flight invocation.
2. Run the packaged shared smoke on that host to validate HTTP result sharing
   and old-ID behavior across two packaged VM lifetimes.
3. Perform the issue's bounded real Claude/Codex MCP-client probe against the
   same authenticated URL and allowed Echo instance. It was not attempted here
   because the server cannot bind. Installed executables alone do not establish
   an authenticated HTTP client round trip.

No HTTP acceptance completion or production readiness is claimed until these
checks can run. The checkout remains reviewable and disabled by default.

## Tosi usability report for joshrotenberg/bottega

Reproduction in this managed `workspace-write`, network-restricted Tosi session:

```sh
elixir -e 'IO.inspect(:gen_tcp.listen(0, [ip: {127,0,0,1}]))'
mix test test/gen_agent_server_shared_mcp_test.exs
MIX_OS_CONCURRENCY_LOCK=0 MIX_QUIET=1 mix gen_agent_server.ops ask --agent echo --prompt probe
```

Observed: the local-only bind returns `{:error, :eperm}`; normal Mix cannot acquire
its filesystem lock; with the lock disabled, Mix still emits
`warning: failed to subscribe to Mix events using TCP, reason: :eperm` on stderr.
Tests combining stdout/stderr then lose their JSON/one-line output contract.
Existing Unix-socket tests also fail on binding. The session has approval policy
`never`, so there is no available approval path for the required local listener.

Impact: a local-listener implementation task can compile and run pure/unit or
stdio tests but cannot perform its specified HTTP acceptance or packaged smoke.
This is an environment capability/usability mismatch, not evidence of a
gen_agent_server HTTP protocol failure. A task profile allowing loopback and
workspace-local Unix listeners, or a clearly advertised route to such a profile,
would make the acceptance criteria executable. The limitation was filed as
[bottega #105](https://github.com/joshrotenberg/bottega/issues/105).

## Final verification outside Tosi

After the worker handoff, the parent session ran the full suite: **137 passed**.
`MIX_ENV=prod mix release --overwrite`, the existing packaged stdio smoke, and
the new packaged shared HTTP smoke all passed. The HTTP test covered two clients,
in-flight disconnect and listener failure isolation. The release smoke covered
cross-client result reads, disconnect, and old IDs after restart. A local
`mix gen_agent_server.ops instances` command also passed with deliberately
malformed shared listener variables, proving that short-lived Mix commands
ignore the release-only listener configuration.

The optional [real-client probe](runs/2026-10-09-shared-mcp-81/real_clients_probe.py)
started one Echo-only packaged release with an ephemeral token. Claude CLI and
Codex CLI each called `instances`, `invoke` and `result` through authenticated
HTTP and returned `echo: real-client-probe`. Their IDs shared the same random
instance namespace, confirming that both reached the same running release.
The first Codex attempt used a read-only/no-approval profile and denied tool
calls locally; retrying with `--approve-for-me` passed. The probe records its
exact prompt, configuration, budget and client commands for reuse. It incurs
real provider usage when run.

Independent Claude high-effort, read-only review found no boundary bypass. It
identified a real startup hazard: exported listener variables caused ordinary
Mix commands to try to bind the shared port. `from_release_env!/1` now restricts
listener startup to packaged releases. The review also identified malformed
non-map arguments returning an internal error; Authorization now fails closed
without raising. Low-priority observations were listener failure reporting,
error payloads after an already-admitted `ask`, and token exposure to same-user
server-environment readers. These are documented limitations, not acceptance
blockers for this loopback, single-operator slice.

Delegation stages: Codex high/read-only design task
`3ada0f45-7948-4135-996b-8965e871e249`; Codex high/workspace-write
implementation task `a0abdb77-0c39-4a24-b221-ffd922ec5631`; Claude
high/read-only independent review task `1d6f0323-ee59-48db-8ad3-7d33039bd874`.
The implementation worker edited only the isolated checkout and could not bind
local sockets; parent verification supplied the missing external checks.

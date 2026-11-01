I’ll inspect the repository instructions and access-option code, update the implementation, tests, and docs, then run every required check and report sandbox failures separately from verified results.

The access defaults are now centralized in `Providers`, and startup agents use that builder too. Inherited options are omitted from backend arguments. I’m updating tests for that omission and keeping explicit read-only review provenance unchanged.

Compilation passed. The test runs have reported sandbox failures from denied socket access and CLI output checks affected by Mix’s TCP warning. One guide assertion also needed updating; that is fixed. I’m finishing the checks and reviewing the final diff for stale default claims.

The focused access tests pass, including all Claude modes, independent Codex sandbox/config settings, startup consistency, schema enums, and configured route descriptions. Fresh and resumed Codex tests also pass for inherited and explicit access. The remaining full-suite failures are tied to the sandbox’s TCP restrictions; no authoritative host run has been performed.

Implemented inheritance defaults across providers, profiles, startup agents, dynamic routes, and patterns.

Changed provider/parsing/schema modules, root and extension tests, and README/MCP guides. Added `test/gen_agent_server_access_test.exs`.

The expanded API accepts Claude `inherit`, `read_only`, `plan`, `accept_edits`, `auto`, `bypass_permissions`, and `dont_ask`; Codex sandbox accepts `inherit`, `read_only`, and `workspace_write`. Inheritance omits access overrides. Codex keeps `approval_policy: :never`; ignoring user config requires explicit `ignore`.

Tests cover defaults, explicit modes, invalid values, profiles, startup consistency, schemas, dynamic descriptions, review provenance, and fresh/resumed Codex arguments. Dependencies and names-only unconfigured descriptions remain unchanged.

Every required check was attempted:

| Exact command | Result |
|---|---|
| `MIX_OS_CONCURRENCY_LOCK=0 mix format` | Passed |
| `MIX_OS_CONCURRENCY_LOCK=0 mix compile --warnings-as-errors` | Passed; TCP subscription warning |
| `MIX_OS_CONCURRENCY_LOCK=0 mix test` | 118/125 passed |
| `(cd extensions/control && MIX_OS_CONCURRENCY_LOCK=0 mix test)` | 93 passed |
| `(cd extensions/mcp && MIX_OS_CONCURRENCY_LOCK=0 mix test)` | 32/33 passed |
| `(cd extensions/patterns && MIX_OS_CONCURRENCY_LOCK=0 mix test)` | 17/18 passed |
| `(cd extensions/peers && MIX_OS_CONCURRENCY_LOCK=0 mix test)` | 0/19 passed |
| `(cd extensions/public_source && MIX_OS_CONCURRENCY_LOCK=0 mix test)` | 7 passed |
| `(cd extensions/schedule && MIX_OS_CONCURRENCY_LOCK=0 mix test)` | 5 passed |
| `(cd extensions/selection && MIX_OS_CONCURRENCY_LOCK=0 mix test)` | 8 passed |

Exact remaining failure causes:

- Root: two Ops CLI timeout tests fail with `Jason.DecodeError` on warning text; five CLI tests fail output/line-count assertions because subprocess output includes `warning: failed to subscribe to Mix events using TCP, reason: :eperm`.
- Patterns: the underscore-timeout `run_pattern` test has the same JSON decoding failure.
- MCP: the shared HTTP client test fails at `:gen_tcp.listen/2` with `{:error, :eperm}`.
- Peers: all 19 tests fail in shared setup with `{:error, :eperm}`.

The six focused access tests pass, and `git diff --check` passes. The authoritative host run remains undone because this session only provides the restricted sandbox; no passing host run is claimed.

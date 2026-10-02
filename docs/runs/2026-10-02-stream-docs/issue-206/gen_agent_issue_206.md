Related: #108 (ship the scripted mock backend).

Found by the 2026-10-01 review at `b8f8ab4` and re-verified against `main` at `1a03608` by a read-only Codex worker in a `gen_agent_server` verification pool (genagent/gen_agent_server#25). One verifier per finding: treat file and line references as the starting point for the fix, and re-check them.

## Problem

The GenAgentEnsemble moduledoc example and a comment in config/runtime.exs present GenAgent.Backends.Mock as a usable backend. The module exists only in test/support of core and, as a verbatim copy, in the ensemble's own test/support. A consumer who copies the example gets an undefined module at agent start.

**Verification on current main.** The ensemble moduledoc uses `GenAgent.Backends.Mock`, and runtime config suggests it for local use (`extensions/ensemble/lib/gen_agent_ensemble.ex:12-16`; `extensions/ensemble/config/runtime.exs:11-18`). Its definitions are only in core and ensemble `test/support` (`test/support/mock_backend.ex:1`; `extensions/ensemble/test/support/mock_backend.ex:1`). Both packages compile those paths only for tests and exclude them from package files (`mix.exs:30-32`, `:82-87`; `extensions/ensemble/mix.exs:30-32`, `:78-88`). Agent initialization calls `backend.start_session/1`, so that backend is undefined in an installed application (`lib/gen_agent/server.ex:147-149`). Ensemble does ship a local demo backend: `GenAgentEnsemble.Backends.Echo` (`extensions/ensemble/lib/gen_agent_ensemble/backends/echo.ex:1-10`).

## Acceptance

- Tests cover each case above.

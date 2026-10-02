Found by the 2026-10-01 review at `b8f8ab4` and re-verified against `main` at `1a03608` by a read-only Codex worker in a `gen_agent_server` verification pool (genagent/gen_agent_server#25). One verifier per finding: treat file and line references as the starting point for the fix, and re-check them.

## Problem

claude_wrapper 0.14.4 declares optional `forcola ~> 0.4.0` and codex_wrapper 0.5.3 declares optional `forcola ~> 0.3.5`. An application using both CLI backends with forcola resolves only by holding claude_wrapper at 0.14.3 and forcola at 0.3.5.

**Verification on current main.** The checked-in Claude integration now requires `claude_wrapper ~> 0.14.5`, rather than 0.14.4 (`integrations/claude/mix.exs:36`). Its lock records optional `forcola ~> 0.4.0` (`integrations/claude/mix.lock:3`); the Codex lock records optional `forcola ~> 0.3.5` (`integrations/codex/mix.lock:3`). Those ranges do not overlap when an application includes Forcola. The proposed workaround is stale: this Claude integration’s `~> 0.14.5` requirement excludes `claude_wrapper 0.14.3` (`integrations/claude/mix.exs:36`).

## Acceptance

- Tests cover each case above.


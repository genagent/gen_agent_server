Related: #72 (token-scoped cancellation) and #106 (stream events with request refs).

Found by the 2026-10-01 review at `b8f8ab4` and re-verified against `main` at `1a03608` by a read-only Codex worker in a `gen_agent_server` verification pool (genagent/gen_agent_server#25). One verifier per finding: treat file and line references as the starting point for the fix, and re-check them.

## Problem

tell/3 results can only be fetched by poll/2 or inbox/1. There is no equivalent of core tell_with_completion/4, no way to interrupt or cancel a pending token short of stop/1, and sub-agent stream events are not exposed. The package's own await helper is a 50 ms polling loop.

**Verification on current main.** Ensemble’s public API exposes `tell`, `ask`, `poll`, `inbox`, `notify`, `status`, and `stop`, with no completion subscription or token cancellation method (extensions/ensemble/lib/gen_agent_ensemble.ex:38-84). It receives core completion messages internally, then stores results for `poll` or `inbox` (extensions/ensemble/lib/gen_agent_ensemble/server.ex:144-169,207-216). The strategy callbacks have no stream event callback (extensions/ensemble/lib/gen_agent_ensemble/strategy.ex:74-82). Its `await` helper sleeps 50 ms between polls (extensions/ensemble/lib/gen_agent_ensemble/iex.ex:127-135).

## Acceptance

- Tests cover each case above.

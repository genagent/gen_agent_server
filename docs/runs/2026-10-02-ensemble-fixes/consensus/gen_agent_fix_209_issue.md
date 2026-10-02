Found by the 2026-10-01 review at `b8f8ab4` and re-verified against `main` at `1a03608` by a read-only Codex worker in a `gen_agent_server` verification pool (genagent/gen_agent_server#25). One verifier per finding: treat file and line references as the starting point for the fix, and re-check them.

## Problem

### Consensus {:at_least, n} reports an arbitrary verdict when two verdicts both meet the threshold

With `{:at_least, n}` and n <= N/2, two verdicts can satisfy the threshold in the same round. check_threshold/2 picks the first maximal entry in map enumeration order, so a tied split is reported as CONSENSUS for whichever atom enumerates first. On OTP 26+ atom key order in small maps follows atom-table order, so the winner is not predictable from the verdict names.

**Verification on current main.** `{:at_least, n}` accepts any threshold from 1 through the agent count, so two verdicts can both qualify (`extensions/ensemble/lib/gen_agent_ensemble/strategies/consensus.ex:124-125`). The code counts verdicts, then `Enum.max_by/3` selects one entry by count without handling ties; any selected count meeting `n` becomes `{:converged, verdict}` (`extensions/ensemble/lib/gen_agent_ensemble/strategies/consensus.ex:191-219`). The reply reports that verdict as `CONSENSUS` (`extensions/ensemble/lib/gen_agent_ensemble/strategies/consensus.ex:296-301`).

### Consensus aborts the whole run on one agent's turn error even when the threshold is still reachable

handle_error/3 fails the token as soon as any panelist's turn errors and discards the other responses. An unparseable response is already tolerated as an abstain, but a transient provider error (rate limit, timeout) from one of N agents is not, which works against the guide's main use case of heterogeneous backends.

**Verification on current main.** I’m checking the error path and how remaining responses are handled.

VERDICT: CONFIRMED

`handle_error/3` immediately sets Consensus to idle and returns `{:reply_error, token, {agent, reason}}`, without checking whether the remaining agents could meet the threshold (`extensions/ensemble/lib/gen_agent_ensemble/strategies/consensus.ex:345-350`). This drops the round’s accumulated responses; later responses for the failed token are ignored once the Server removes it from `pending` (`server.ex:472-473,514-522,689-690`). By comparison, an unparseable response becomes an abstain (`consensus.ex:166-173`). The guide explicitly presents heterogeneous backends as a use case (`guides/workflows/consensus.md:187-192`).

## Acceptance

- Tests cover each case above.


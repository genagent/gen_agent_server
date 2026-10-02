Found by the 2026-10-01 review at `b8f8ab4` and re-verified against `main` at `1a03608` by a read-only Codex worker in a `gen_agent_server` verification pool (genagent/gen_agent_server#25). One verifier per finding: treat file and line references as the starting point for the fix, and re-check them.

## Problem

### Checkpointer guide applies a queued or duplicate review to a draft the reviewer has not seen

Review events carry no step or draft identity and are matched only on phase. A review that arrives while a turn is in flight is deferred by the runtime and drained after handle_response/3 has set phase back to :awaiting_review, so it is applied to the new draft. A double-sent approve advances two steps with one human decision.

**Verification on current main.** Review handlers match the decision and `:awaiting_review` phase, with no step or draft identifier (guides/patterns/checkpointer.md:100-131). The runtime queues notifications received during processing (lib/gen_agent/server.ex:764-769). After `handle_response/3` stores the new draft and sets `:awaiting_review` (guides/patterns/checkpointer.md:79-97), it drains those notifications against the updated state (lib/gen_agent/server.ex:1274-1284). An early review can therefore apply to an unseen draft. A duplicate approve arriving during the turn started by the first approval can advance the next step too. Two approvals already queued together behave differently: the second sees `:drafting` and is ignored.

### Checkpointer guide agent is stuck in :drafting after a failed turn

Checkpointer.Agent defines no handle_error/3. When a turn fails the default returns {:noreply, state}, phase stays :drafting, and every review event falls through to the catch-all clause. The manager loop described in the guide ('wait for phase: :awaiting_review') never completes and nothing in agent state records the failure.

**Verification on current main.** The example starts with `phase: :drafting` and changes it to `:awaiting_review` only in `handle_response/3` (guides/patterns/checkpointer.md:49–57, 79–97). It defines no `handle_error/3`, so `use GenAgent` supplies `{:noreply, state}`; the server retains that state after a failed turn (lib/gen_agent.ex:410–416; lib/gen_agent/server.ex:1304–1334). All review clauses require `:awaiting_review`, leaving review events to the catch-all while the phase remains `:drafting` (guides/patterns/checkpointer.md:103–131). The suggested wait for `:awaiting_review` would therefore persist (guides/patterns/checkpointer.md:159–165). The request’s ref can report the error, but the example discards it.

### Checkpointer scenario test exercises a different protocol from the guide

The scenario agent and the guide agent differ in event shapes, state fields, step numbering, phase names and the completion condition, so the test does not validate the code users copy. It also has no case for a review during :processing or for a failed turn.

**Verification on current main.** I’m comparing the scenario test with the guide’s callback code.

VERDICT: CONFIRMED

The test sends `:approve`, `{:revise, hint}`, and `:finish` (`test/scenarios/checkpointer_scenario_test.exs:68–90`); the guide handles `{:review, ...}` events (`guides/patterns/checkpointer.md:103–131`). The test uses zero-based `step`, `drafts`, and `:running`/`:finished`; the guide uses one-based `current_step`, `draft`/`history`/`feedback`, and `:drafting`/`:done` (`test/scenarios/checkpointer_scenario_test.exs:31–40`; `guides/patterns/checkpointer.md:49–67`). Their final-approval checks are expressed differently but are equivalent after accounting for numbering. The three test cases cover approval, revision, and early finish, with no review during processing or failed turn (`test/scenarios/checkpointer_scenario_test.exs:112–182`).

## Acceptance

- Tests cover each case above.

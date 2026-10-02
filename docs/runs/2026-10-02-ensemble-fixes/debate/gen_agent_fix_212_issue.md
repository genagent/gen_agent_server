Found by the 2026-10-01 review at `b8f8ab4` and re-verified against `main` at `1a03608` by a read-only Codex worker in a `gen_agent_server` verification pool (genagent/gen_agent_server#25). One verifier per finding: treat file and line references as the starting point for the fix, and re-check them.

## Problem

The prompt for every turn after the first is the other agent's raw response text. The second agent is never shown the caller's question and neither agent is told that the text is the opponent's turn, so the debate depends on the opener restating the topic and on system prompts.

**Verification on current main.** The caller’s prompt is dispatched only to the first agent (`extensions/ensemble/lib/gen_agent_ensemble/strategies/debate.ex:111-114`). Every later dispatch passes only `response.text` to the other agent (`debate.ex:131-142`). The strategy’s options include agent specs, turn order, round limit, convergence, and final reply shaping, but no prompt framing function (`debate.ex:12-29,62-102`). A test confirms the second agent receives the first response rather than the original prompt (`extensions/ensemble/test/gen_agent_ensemble/strategies/debate_test.exs:87-93`). The opener could repeat the topic, and agent system prompts can supply context; the strategy itself supplies neither the original question nor an opponent-turn label.

## Acceptance

- Tests cover each case above.


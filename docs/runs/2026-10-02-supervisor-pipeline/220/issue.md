# feat(ensemble): keep intermediate Pipeline stage output

Related: #174 (usage on multi-agent replies). The gen_agent_server roadmap (#71) also notes that intermediate Pipeline text is not retained.

Found by the 2026-10-01 review at `b8f8ab4` and re-verified against `main` at `1a03608` by a read-only Codex worker in a `gen_agent_server` verification pool (genagent/gen_agent_server#25). One verifier per finding: treat file and line references as the starting point for the fix, and re-check them.

## Problem

Pipeline forwards response.text to the next stage and drops the rest of each intermediate Response. The caller receives the final stage's Response, whose usage and duration_ms cover one stage only. An application cannot account for the cost of a pipeline run or show intermediate results without writing a custom strategy.

**Verification on current main.** Pipeline passes only `response.text` to the next stage and returns the final stage’s unmodified `Response` (`extensions/ensemble/lib/gen_agent_ensemble/strategies/pipeline.ex:78-89`). Its state retains no earlier responses (`pipeline.ex:30-43`), so the reply’s `usage` and `duration_ms` describe the final turn, not the whole run (`lib/gen_agent/response.ex:8-15`). The final sentence overstates the limitation: a custom **agent callback**, without a custom strategy, can capture each turn’s full response through `handle_response/3` or `post_turn/3` (`lib/gen_agent/server.ex:1255-1269`).

## Acceptance

- Tests cover each case above.


https://github.com/genagent/gen_agent/issues/220

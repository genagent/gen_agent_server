# fix(ensemble): bound Supervisor fan-out independently of coordinator output

In gen_agent_server dogfooding this was worked around with a capped decomposer (`max_subtasks`); the strategy itself has no limit.

Found by the 2026-10-01 review at `b8f8ab4` and re-verified against `main` at `1a03608` by a read-only Codex worker in a `gen_agent_server` verification pool (genagent/gen_agent_server#25). One verifier per finding: treat file and line references as the starting point for the fix, and re-check them.

## Problem

decompose/3 starts one worker agent and one parallel provider call per element the decomposer returns, with no upper limit. The recommended decomposer splits LLM output on newlines, so a long or malformed coordinator reply directly sets the number of processes, sessions and concurrent API calls. Worker starts also run serially inside the Server process.

**Verification on current main.** I’m checking the fan-out path, guide example, and Server operation order.

VERDICT: CONFIRMED

`decompose/3` passes the coordinator’s text to the decomposer, then creates a start and dispatch operation for every returned sub-prompt, with no count check (`extensions/ensemble/lib/gen_agent_ensemble/strategies/supervisor.ex:103-126`). The guide’s example splits that text on newlines (`guides/workflows/supervisor.md:73-86`). The Server applies those operations serially, including each `DynamicSupervisor.start_child` call (`lib/gen_agent_ensemble/server.ex:358-360,412-420`). Each accepted dispatch starts an asynchronous backend prompt task, so the resulting calls can overlap (`lib/gen_agent/server.ex:869-893,911-922`).

## Acceptance

- Tests cover each case above.


https://github.com/genagent/gen_agent/issues/214

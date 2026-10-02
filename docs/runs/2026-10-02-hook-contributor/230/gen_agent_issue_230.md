Found by the 2026-10-01 review at `b8f8ab4` and re-verified against `main` at `1a03608` by a read-only Codex worker in a `gen_agent_server` verification pool (genagent/gen_agent_server#25). One verifier per finding: treat file and line references as the starting point for the fix, and re-check them.

## Problem

The pre_run/1 @doc says the hook blocks the first turn but does not block start_agent/2. It does not say that status/2, poll/3, tell/3, runtime_snapshot/2 and every other call also wait until the hook returns, with a default timeout of :infinity. The pre_turn/2 @doc recommends sleeping for rate limiting, which has the same effect on each dispatch. There is no table stating which callbacks run in the agent process and which run in the prompt task.

**Verification on current main.** I’ll compare the hook docs with the call and dispatch paths.

VERDICT: CONFIRMED

`pre_run/1` runs in the agent process; the server explicitly says external calls queue until it returns (`lib/gen_agent/server.ex:49`). `pre_turn/2` runs synchronously before prompt task dispatch (`lib/gen_agent/server.ex:836`). The cited hook docs omit the effect on `status/2`, `poll/3`, `tell/3`, and other synchronous calls, whose default timeout is `:infinity` (`lib/gen_agent.ex:291`, `lib/gen_agent.ex:460`). There is no callback process-location table. **Qualification:** asynchronous casts such as `notify/2` return immediately (`lib/gen_agent.ex:690`); “every call” applies to synchronous agent calls.

## Acceptance

- Tests cover each case above.

# docs(ensemble): document the Strategy callbacks the server actually calls

Found by the 2026-10-01 review at `b8f8ab4` and re-verified against `main` at `1a03608` by a read-only Codex worker in a `gen_agent_server` verification pool (genagent/gen_agent_server#25). One verifier per finding: treat file and line references as the starting point for the fix, and re-check them.

## Problem

GenAgentEnsemble.Strategy is the public extension point but none of its callbacks has a @doc. Unstated facts a strategy author needs: callbacks run inside the Server process (a raise or a bad return shape crashes the session, a blocking call blocks every caller); what happens when each optional callback is missing; init/1 may return {:error, reason}, which the Server handles but the callback type excludes; handle_status/1 output is merged over the base status map and can replace its keys; handle_response/3 does not receive the token, so strategies must keep their own agent to token mapping.

**Verification on current main.** The behaviour declares callbacks without individual `@doc` entries, and types `init/1` only as a success tuple (`extensions/ensemble/lib/gen_agent_ensemble/strategy.ex:72-90`). The Server also accepts `{:error, reason}` from `init/1` (`extensions/ensemble/lib/gen_agent_ensemble/server.ex:70-71`, `:107-109`). It calls strategy handlers inside its own callbacks and strictly matches their return shape, so blocking or raising affects the Server (`server.ex:122-141`, `:671-674`). Optional callbacks have different fallbacks, including logging an unhandled error and leaving state unchanged (`server.ex:314-335`). Status extras can overwrite base keys (`server.ex:172-188`). `handle_response/3` receives the agent and response, not the token (`server.ex:299-306`), although the module overview does tell authors to correlate tokens (`strategy.ex:46-52`).

## Acceptance

- Tests cover each case above.


https://github.com/genagent/gen_agent/issues/205

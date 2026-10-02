# feat(api): list running agents

A Claude and Codex debate run through gen_agent_server on 2026-10-01 converged on a narrow first step: `GenAgent.list/0` returning registered names as a point-in-time view, with module and backend metadata added only when a caller needs it. Metadata alone does not tell an application which supervisor owns an agent. Four sibling applications currently call `Registry.select/2` on `GenAgent.Registry` directly.

Found by the 2026-10-01 review at `b8f8ab4` and re-verified against `main` at `1a03608` by a read-only Codex worker in a `gen_agent_server` verification pool (genagent/gen_agent_server#25). One verifier per finding: treat file and line references as the starting point for the fix, and re-check them.

## Problem

The public API has whereis/1 only. Enumerating agents requires selecting from the internal GenAgent.Registry, and neither the registry entry, status/2 nor runtime_snapshot/2 reports the callback module, backend, start time or caller-supplied tags.

**Verification on current main.** I’m checking the public API and registry implementation against the claim.

VERDICT: CONFIRMED

`GenAgent` exposes `whereis/1` for lookup by name, but no public function to enumerate agents (`lib/gen_agent.ex:868`). Registration uses the name alone (`lib/gen_agent.ex:879`); other caller options are forwarded to `init_agent/1`, with no tag field (`lib/gen_agent.ex:531`). `status/2` returns operational fields and callback state, while `runtime_snapshot/2` returns bounded runtime fields. Neither has dedicated callback module, backend, agent start time, or tag fields (`lib/gen_agent/server.ex:364`, `lib/gen_agent/server.ex:381`).

## Acceptance

- Tests cover each case above.


https://github.com/genagent/gen_agent/issues/256

Found by the 2026-10-01 review at `b8f8ab4` and re-verified against `main` at `1a03608` by a read-only Codex worker in a `gen_agent_server` verification pool (genagent/gen_agent_server#25). One verifier per finding: treat file and line references as the starting point for the fix, and re-check them.

## Problem

### Supervisor guide never stops its workers; each run leaves N halted agents registered and a rerun under the same coordinator name crashes

The guide states that workers self-halt "so the coordinator doesn't have to track or stop them explicitly". `{:halt, state}` only freezes the mailbox; the process, its Registry entry and its backend session stay alive. The usage block stops only the coordinator. Worker names are derived from the coordinator name, so a second run with the same name fails inside `handle_response/3`.

**Verification on current main.** The guide says worker self-halt removes the need to stop them (guides/patterns/supervisor.md:68–70), but `{:halt, state}` leaves the process idle with `halted: true` (lib/gen_agent/server.ex:1171–1180, 1290–1293). The usage block stops only the coordinator (guides/patterns/supervisor.md:273–299). Workers use names derived from the coordinator name, and startup is pattern-matched on `{:ok, _pid}` (guides/patterns/supervisor.md:207–220). Reusing that name while the old workers remain registered makes worker startup fail inside the coordinator’s `handle_response/3` (guides/patterns/supervisor.md:124–132).

### Supervisor guide hard-codes GenAgent.Backends.Anthropic for workers; coordinator crashes when that package is not a dependency

`spawn_workers/2` starts every worker with `backend: GenAgent.Backends.Anthropic` regardless of the backend the coordinator was started with. A user who runs the coordinator on Claude, Codex, OpenAI or a test backend without `gen_agent_anthropic` installed gets a MatchError inside `handle_response/3`, which stops the coordinator.

**Verification on current main.** In the guide’s callback recipe, the coordinator calls `spawn_workers/2` after planning (guides/patterns/supervisor.md:124-132). That function hard-codes `GenAgent.Backends.Anthropic` and matches worker startup against `{:ok, _pid}` (guides/patterns/supervisor.md:207-218). The coordinator’s backend is not passed to it. Anthropic is absent from the core package dependencies (mix.exs:34-40); server startup calls `backend.start_session/1` (lib/gen_agent/server.ex:147-148). Without that backend available, worker startup fails and the match in the coordinator callback raises. The separate shipped Ensemble example accepts a configurable worker backend (guides/patterns/supervisor.md:20-29).

### Phase-dispatched handle_response/3 in Supervisor.Coordinator and Research.Agent has no fallback clause; an extra ask or tell crashes the agent

`Supervisor.Coordinator.handle_response/3` only matches phases :planning and :synthesizing. While the coordinator is idle in :collecting (not halted), any `ask`/`tell` dispatches a turn whose response has no matching clause, raising FunctionClauseError in the agent process. `Research.Agent` has the same gap for phases :done and :failed after `GenAgent.resume/1`.

**Verification on current main.** In the guide’s callback recipe, `Supervisor.Coordinator` handles responses only in `:planning` and `:synthesizing`, yet planning can leave it in `:collecting` without halting (guides/patterns/supervisor.md:124, guides/patterns/supervisor.md:139, guides/patterns/supervisor.md:148). The server dispatches an `ask` or `tell` when idle and unhalted, then calls `handle_response/3` without catching a missing clause (lib/gen_agent/server.ex:264, lib/gen_agent/server.ex:281, lib/gen_agent/server.ex:1255). `Research.Agent` likewise has no response clause for its terminal `:done` or `:failed` phases; `resume/1` clears the halt flag and permits another turn (guides/patterns/research.md:86, guides/patterns/research.md:119, guides/patterns/research.md:131, lib/gen_agent/server.ex:486).

### Supervisor guide coordinator waits in :collecting with no bound when a worker dies or a result notify is dropped

`maybe_synthesize/1` proceeds only when results plus failures equal the worker count. Workers report through `handle_response/3` and `handle_error/3`, which covers turn failures, but a worker process that exits (crash in a callback, external stop) or a `notify/2` that is rejected never produces a report. The coordinator does not monitor workers and has no timeout, so it stays idle in :collecting.

**Verification on current main.** I’ll check the coordinator’s completion logic and the worker reporting path.

VERDICT: CONFIRMED

This affects the guide’s callback example, which is separate from the shipped Ensemble strategy (`guides/patterns/supervisor.md:36`). Its coordinator enters `:collecting`, then synthesizes only after reports equal the worker count (`guides/patterns/supervisor.md:139`, `guides/patterns/supervisor.md:170`). Workers report through `GenAgent.notify/2`; the example adds no worker monitor or collection timeout (`guides/patterns/supervisor.md:207`, `guides/patterns/supervisor.md:259`). A dead worker can therefore leave it waiting indefinitely. `notify/2` can also silently reject a queued notification (`lib/gen_agent.ex:685`).

### Supervisor guide defines its modules inside Elixir's Supervisor namespace

The guide's modules are named `Supervisor.Coordinator` and `Supervisor.Worker`, and the worker's option and state field holding the coordinator name is `:supervisor`. This places application modules under the standard library's `Supervisor` module name and overloads an OTP term for something that does not supervise processes.

**Verification on current main.** The guide defines `Supervisor.Coordinator` and `Supervisor.Worker`, placing both under Elixir’s `Supervisor` namespace (guides/patterns/supervisor.md:81–84, 229–230). It passes the coordinator’s name as `supervisor:` to the worker (guides/patterns/supervisor.md:207–217). The worker stores that value in `state.supervisor` and uses it as the recipient of `GenAgent.notify/2` (guides/patterns/supervisor.md:232–240, 259–267). In this example, that field names the coordinator, not an OTP supervisor.

## Acceptance

- Tests cover each case above.

Found by the 2026-10-01 review at `b8f8ab4` and re-verified against `main` at `1a03608` by a read-only Codex worker in a `gen_agent_server` verification pool (genagent/gen_agent_server#25). One verifier per finding: treat file and line references as the starting point for the fix, and re-check them.

## Problem

### Pool.submit/2 crashes with MatchError when a worker's bounded mailbox rejects the prompt; the "backpressure for free" text predates 0.3

`submit/2` matches `{:ok, ref} = GenAgent.tell(worker, task)`. Since bounded pending inputs landed, `tell/3` returns `{:error, {:overloaded, info}}` when a worker has 1,000 queued prompts or 1 MiB of queued prompt bytes (defaults). The guide still describes the mailbox as unbounded buffering and gives the dispatcher no way to set the limits or handle the rejection.

**Verification on current main.** `Pool.submit/2` pattern-matches `{:ok, ref}` from `GenAgent.tell/2` (guides/patterns/pool.md:152–159). A busy worker’s pending queue can reject a prompt with `{:error, {:overloaded, info}}`, causing that match to raise (lib/gen_agent/server.ex:639–649). The defaults are 1,000 pending prompts and 1,048,576 prompt bytes (lib/gen_agent/server.ex:24–25); the limits were added in 0.3.0 (CHANGELOG.md:29–35). `Pool.start/2` passes only name, backend, worker name, and role, so its options cannot configure those limits (guides/patterns/pool.md:124–139). The guide promises fire-and-forget queueing (guides/patterns/pool.md:46–59), though it does not explicitly call the mailbox unbounded.

### Pool guide drops failed tasks from results because Pool.Worker has no handle_error

`Pool.Worker` records results only in `handle_response/3`. A failed turn goes to the default `handle_error/3`, which records nothing, so `Pool.results/1` silently undercounts and gives no indication which task failed. The failure is visible only by polling the individual ref.

**Verification on current main.** In the guide’s callback recipe, `Pool.Worker` adds entries only in `handle_response/3` and defines no `handle_error/3` (guides/patterns/pool.md:80-113). The inherited error handler leaves state unchanged (lib/gen_agent.ex:415-416). `Pool.results/1` reads only that results list, so failed tasks are absent from its counts and have no failure marker (guides/patterns/pool.md:176-184). The submitted ref can be polled for an error (guides/patterns/pool.md:148-159; lib/gen_agent.ex:656-675). “Only” is slightly too strong: turn-error telemetry also reports failures (lib/gen_agent/server.ex:1489-1495).

### Pool guide small defects: counter read and increment are not atomic, variation text says halt where stop is needed, status/1 polling copies results

The guide advertises "round-robin dispatch via an atomic counter" but reads and increments in two operations, so concurrent submitters can pick the same worker. The Auto-scaling variation says to "halt the extras", which leaves processes alive. `wait_for_all/2` and the work-stealing variation use `status/1`, which copies each worker's accumulated results on every poll. The work-stealing text refers to `next_idx`, a name not present in the code.

**Verification on current main.** The guide calls dispatch atomic, but `submit/2` reads and increments the counter in separate operations, allowing concurrent callers to read the same index (guides/patterns/pool.md:60, guides/patterns/pool.md:152). `wait_for_all/2` repeatedly calls `status/1`, which returns the worker’s full `agent_state`, including its growing results list; the work-stealing variation proposes more status calls (guides/patterns/pool.md:190, lib/gen_agent/server.ex:364, guides/patterns/pool.md:240). That variation names `next_idx`, while the implementation uses `idx` (guides/patterns/pool.md:153, guides/patterns/pool.md:241). Auto-scaling says to “halt” extras, but halting leaves processes alive; the guide’s `stop/1` actually terminates them (guides/patterns/pool.md:250, guides/patterns/pool.md:186, lib/gen_agent.ex:88).

## Acceptance

- Tests cover each case above.

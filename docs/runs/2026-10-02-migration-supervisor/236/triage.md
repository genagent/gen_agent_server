All five claims still hold at HEAD `0a970d4`, and none have been fixed. Some line numbers differ from the issue's, so the ones below are from this checkout. I made no edits; the model also wrote an untracked private plan file outside this run record.

## What still holds

1. **Workers are never stopped, and a rerun crashes.**
   - The guide says self-halt removes the need to stop workers (`guides/patterns/supervisor.md:68-70`). But `{:halt, _}` only sets `halted: true` (`lib/gen_agent/server.ex:1662-1668`), so the process and its Registry entry stay alive.
   - The usage block stops only the coordinator (`supervisor.md:298`).
   - Worker names come from the coordinator name, and startup is a bare `{:ok, _pid} =` match (`supervisor.md:211-213`). That match runs inside planning `handle_response` (`:132`).
   - `handle_response/3` is not rescued (`server.ex:1766-1767`), so a rerun under the same name raises and stops the coordinator.
2. **Workers always get `GenAgent.Backends.Anthropic`.**
   - The backend is hard-coded at `supervisor.md:215`, and Anthropic is not a core dependency (`mix.exs:34-40`).
   - The coordinator cannot copy its own backend to workers: `:backend` and `:name` are removed before `init_agent/1` runs (`lib/gen_agent.ex:551-564`). The worker backend has to be its own option.
3. **No fallback `handle_response` clause.**
   - The coordinator handles only `:planning` and `:synthesizing` (`supervisor.md:124, 148`). In `:collecting` it is idle and not halted, so an `ask` or `tell` is dispatched (`server.ex:356, 373`) and the missing clause raises at `server.ex:1767`.
   - `Research.Agent` has no clause for `:done` or `:failed` (`research.md:86, 119, 131`). `resume/1` clears the halt flag (`server.ex:699-701`), so the next turn crashes it.
4. **`:collecting` has no time limit.**
   - `maybe_synthesize` waits until the number of reports equals the number of workers (`supervisor.md:170-183`). There is no monitor and no timeout.
   - A rejected `notify` only emits telemetry (`server.ex:942-967`), so the coordinator never learns about it.
5. **Modules sit under Elixir's `Supervisor` namespace.**
   - The modules are `Supervisor.Coordinator` and `Supervisor.Worker` (`supervisor.md:81, 84, 229`).
   - The worker's coordinator name is passed and stored as `supervisor:` (`:217, 233, 240, 261, 267`).

## Limits of the public API

- **No monitors or timers inside the callback module.** The server drops every info message it doesn't own (`server.ex:786`), and GenAgent has no `handle_info` callback. The coordinator therefore needs a small helper process ("watcher"). It turns a worker exit or a deadline into a `GenAgent.notify_ack/3` call, and retries if the coordinator's queue is full.
- **Cleanup after an external stop has to be asynchronous.** When someone calls `GenAgent.stop(coordinator)`, `terminate_agent` runs while the supervisor is waiting on the coordinator. Calling `GenAgent.stop` on workers from there would deadlock. The watcher stops the workers after the coordinator goes down. Per-run unique worker names make an immediate rerun safe either way.

## Smallest fix

**`guides/patterns/supervisor.md`**
- Rename the modules to `Fanout.Coordinator` and `Fanout.Worker`, and rename the `:supervisor` option and field to `:coordinator`.
- Add three options: `worker_backend:` (required), `worker_opts:` and `collect_timeout:`.
- Name workers `"#{coord}-#{run}-worker-#{i}"`, where `run` is a unique integer per run. Tag every event with `run` and ignore events from an earlier run.
- In `spawn_workers`, handle `{:error, reason}`: stop any workers already started and halt as `:failed`.
- Add the watcher process, which:
  - reports a dead worker as `{:worker_down, run, name, reason}`;
  - sends `{:collect_timeout, run}` at the deadline, after which unreported workers count as `:timeout`;
  - stops all workers if the coordinator goes down.
- Route every halt through one `finish/3` helper that stops each worker with `GenAgent.stop/1` and stops the watcher.
- Add a catch-all `handle_response`: keep collecting in `:collecting`, halt again in `:done` or `:failed`. Let `handle_error` change the phase only during `:planning` or `:synthesizing`.
- Workers keep reporting with `notify/2`. If a report is dropped, the deadline still ends collection.
- Correct the text at :68-70, add a short "Failure and cleanup" section covering the two limits above, and change the usage block to use `worker_backend:` with a bounded status poll.

**`guides/patterns/research.md`**
- Add a catch-all clause for `:done` and `:failed` that halts again and leaves the report alone.
- Make `handle_error` in those phases record `last_error` without changing the phase.
- Add one line of prose about this.

**`test/guides/supervisor_test.exs` (new)**
- Load the guide's code blocks the same way `test/guides/heartbeat_test.exs:1-11` does, and drive them with a local scripted backend.
- Cover:
  - success, with all workers unregistered afterwards;
  - partial failure, and all workers failing;
  - a killed worker;
  - the deadline with a blocked worker;
  - cleanup after an external stop;
  - two back-to-back runs under the same coordinator name;
  - an extra `ask` while collecting;
  - a worker start failure.

**`test/guides/research_test.exs` (new)**
- Cover the success path, plus `resume` followed by `ask` after `:done` and after `:failed`. The agent should stay alive with its report unchanged and end up halted again.

No changes to `lib/` or to `test/scenarios/supervisor_scenario_test.exs`, which uses its own copy of the modules.

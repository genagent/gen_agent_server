## Review of PR #351 (issue #315)

### 1. Acceptance items

| Item | Verdict | Where |
|---|---|---|
| `start/3` applies `execute/3`'s validation and rejects before spawning | **Met.** It is stricter than `execute/3`: it always requires `run_evidenced/5` and also calls `check_evidenced/2`. Both are documented. | `query.ex:1145-1185`, `run.ex:171-172`; test `run_test.exs` "preflight" (checks a `calls` file is never written) |
| Frames reach the owner in stream order; mailbox policy documented | **Met.** One sender (`work/3`) feeds one GenServer, which delivers in order. The policy is in the "Frames" section of the moduledoc. | `run.ex:320-328`, `run.ex:510-520`, moduledoc "Frames"; test "slow owner" |
| `snapshot/1` does not block on the child | **Met.** It is answered from the GenServer's state, and no handler waits on the child. | `run.ex:332`; test "snapshot answers while the child is blocked" |
| `await/2` returns the same categories plus exactly one evidence record; its timeout does not cancel | **Met.** One record is built in `run_prepared` or in the EXIT path and published only from `finish/3`. | `query.ex:1208-1231`, `run.ex:450-480`; tests "an await timeout leaves the run going" and "exactly one record" assertions |
| `cancel/2` is idempotent, records the cancellation, reports the runner's cleanup facts | **Met.** With Forcola 0.7, cleanup is always `:unknown` (no report after the port closes, see forcola#93). That is the honest value but not a confirmed one. | `run.ex:334-343`, `forcola_evidence.ex:176-177`, `collector.ex:129-136` |
| Owner exit cancels the run | **Met** | `run.ex:296`, `run.ex:396-402`; test "owner exit" |
| Fake-executable tests for success, failure, timeout, cancel before/after output, owner exit | **Met.** They are tagged `:forcola_evidence`, which runs by default, so I can't confirm they pass by reading alone. | `test/claude_wrapper/run_test.exs` |

### 2. Defects

1. **A cancel can override a completed run, contrary to the docs** (`run.ex:84`, `run.ex:327-328`). The moduledoc says a run that completes natively before the cancel takes effect keeps its own outcome.
   - What happens: `run_prepared` returns only after `Telemetry.span_exec` runs its stop handlers. If the grace timer fires in that window (slow or blocking handler), the worker is killed after the runner already returned.
   - Result: the outcome becomes `:cancelled`, and the runner's real facts are thrown away (exit 0, `cleanup: :confirmed`).
   - The test "a worker killed after its runner returned" asserts this behaviour, so the code and the docs disagree.
   - Fix: report to the run process inside the span callback, before the stop handlers run. For example, add a `:report` fun in `extra`, called with `{reply, evidence}` right after `evidence_record/4` at `query.ex:1226`. Otherwise, qualify the doc sentence.

2. **Exit signals from anything other than the worker are swallowed** (`run.ex:384`). Because of `trap_exit`, `Process.exit(run.pid, :shutdown)` from a host's shutdown logic becomes a message that is ignored. The run cannot be stopped by an exit signal short of `:kill`. A `:kill` skips `prepared.cleanup` and the terminal record.
   - Fix: for a non-worker `{:EXIT, _, reason}` with `outcome == nil`, call `request_cancel/1` and set `stop_when_done: true`. With an outcome already set, return `{:stop, reason, state}`.

3. **Finished runs live as long as their owner** (`run.ex:100`). This is documented, but there is no way to free one. A long-lived owner, such as a GenServer issuing many runs, accumulates one process per run, each holding the full outcome, evidence and stdout up to the runner's bound.
   - Fix: add `Run.release/1` (stop once finished), or a `:linger_ms` option after which a finished run process stops.

4. **`:run_start_failed` skips the execution observer's record** (`run.ex:186-191`). Preflight has already passed at this point, so a valid `:execution_observer` gets no record. That breaks the documented "receives one record" contract. It is practically unreachable, since `init/1` always returns `{:ok, _}`.
   - Fix: send `Runner.not_started_evidence()` built through `ExecutionEvidence.from_native` to `prepared.observers.execution` before returning.

5. **Two new `:io` reasons are undocumented** (`run.ex:190`, `run.ex:367`). `{:run_start_failed, reason}` and `{:run_down, reason}` (worker crashed while not cancelling) appear in neither the `Error` moduledoc nor the `Run` moduledoc. Fix: list both next to `{:helper_down, reason}` in `error.ex`.

6. **The cancelled translation drops `observer_error`** (`forcola_evidence.ex:176-177`). `helper_down` and `done` both go through `observer_outcome/2`. `{:cancelled, stats}` does not, so an observer failure (which includes the Run frame callback) is silently lost on cancel. Fix: keep `:cancelled` as the outcome but carry the error into the evidence, or document that cancel discards it.

7. **Minor inconsistencies**
   - `snapshot/2` (`run.ex:202`) lacks the `timeout_value?` guard that `await/2` and `cancel/2` have.
   - `collector.ex:34` and `run.ex:84` are over-long doc and comment lines that `mix format` won't reflow.

### 3. Changes beyond the issue

All of these should stay:
- The `check_evidenced/2` optional callback and its Forcola implementation. Acceptance item 1 needs it to reject invalid runner options before spawning.
- The `run_evidenced` refactor into `evidenced_runner/1` and `evidenced_args/2`. It is shared by the new preflight path and behaviour-preserving.
- `:events_to`, `:max_queued_frames`, `:cancel_grace_ms` and `snapshot.frames_dropped`. They implement the mailbox policy and the cancel backstop.
- The `{:error, :cancelled}` reply mapping, the new `Error` kinds and the `ExecutionEvidence` reason.
- The README, CLAUDE.md and mix.exs doc-group entries.

REQUEST CHANGES

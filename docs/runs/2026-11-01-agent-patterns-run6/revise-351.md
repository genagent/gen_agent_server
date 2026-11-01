Follow-up on your PR #351. An independent review (Claude, read-only) of 6c0650d requested changes. Its defects section follows verbatim. Fix the ones you agree with, each with a test where behaviour changes; for any you decline, give the reason in your report and in the PR body. Items 1 and 2 are the important ones. For item 3, a small explicit release or linger option is fine; keep the scope small.

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


When the fixes pass every local CI check, push, and before marking the PR ready again, start a fresh read-only Codex reviewer through the agent server the same way as before (a new session name, review-351-confirm) and ask it to confirm these fixes and look for defects they introduce. Address what it finds that you agree with, then stop that session. Same rules as before for identity, trailers, prose, cleanup and CI. Update the PR body. Report commits, checks, CI status, each item resolved or declined, and the reviewer's findings.

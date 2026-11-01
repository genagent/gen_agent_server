You are reviewing a change to claude_wrapper, an Elixir wrapper for the Claude Code CLI, in an open pull request; it is already committed . The current directory is the worktree with the change applied. You can read any file. You cannot run commands; the operator runs the checks.

Review the change against the issue below. Report:
1. For each acceptance item: met, not met, or not verifiable by reading, with the file and line that shows it.
2. Defects: incorrect behaviour, races, missing cases, inconsistencies with the surrounding code's conventions, doc claims the code does not support. For each, file:line, what is wrong, and a concrete fix.
3. Anything in the diff that the issue did not ask for, and whether it should stay.
4. A verdict on the last line: APPROVE or REQUEST CHANGES.

Report only what you can point to in the code. Before calling code dead or unused, search the whole repository, including extensions and tests. Do not restate the change.


This is a second review. An earlier review of commit 6c0650d raised the items below; commits 03ed771 and 77a00f3 respond to them and to a confirmation review that found three more. Check that each item is resolved (or that the decline for item 6 is documented), and look for defects the two new commits introduce. Focus on lib/claude_wrapper/run.ex, lib/claude_wrapper/query.ex and their tests.

## Earlier items
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


## Implementer's account of the fixes
## Items from the review of 6c0650d
1. **A cancel could override a finished run: fixed.** The worker now reports its outcome before telemetry stop handlers run, so a slow handler can't turn a finished run into a cancellation. The test fails with the fix removed.
2. **Exit signals were ignored: fixed.** An exit signal like `:shutdown` now cancels a running run, and the run process stops with that reason once the run ends; on a finished run it stops at once. A `:normal` signal from another process is ignored, as it would be without trapping exits. Tested.
3. **Finished runs lived as long as their owner: fixed.** Added `release/1`: the run process stops once the run has ended, and it does not cancel the run. Tested.
4. **No record on `:run_start_failed`: fixed.** The observer now gets a not-started record. There is no test because the path can't be reached: starting the run process never fails.
5. **Two `:io` reasons undocumented: fixed.** `{:run_start_failed, reason}` and `{:run_down, reason}` are in the `Error` and `Run` docs.
6. **Observer error dropped on cancel: documented, not carried.** The evidence record has no field for an observer failure, and adding one widens a public struct beyond this issue. The docs now say a requested cancel stays the outcome. This reason is in the PR body.
7. **Snapshot timeout guard and long lines: fixed.**

## Confirmation review (`review-351-confirm`, Codex, now stopped)
It confirmed items 1 to 7, found three new defects that I agreed with and fixed in `77a00f3`, and gave a final verdict of request changes:
- **P1:** a worker still blocked in a telemetry handler outlived `release/1` and owner exit. The run process now ends it when it stops, and at the cancel grace, without changing a stored outcome.
- **P2:** a run process stopping with an arbitrary reason during a call made the caller exit. Any non-timeout exit now returns `:not_found`.
- **P2:** `release/1` could return `:timeout` despite documenting `:ok`. It is now an asynchronous request that always returns `:ok`.

The three new regression tests each fail with their fix reverted. I also took its three nits: a gated runner instead of a sleep in the release test, clearer docs on what `:events_to` receives, and long doc lines.



# Issue #315
## feat: add an async one-shot run handle with await, snapshot and cancel

There is no handle for a one-shot run. `Query.execute/2,3` blocks the caller until the run ends, and the only way to stop it early is to end the calling process. A host that wants to start a run, keep working, look at its progress and cancel it has to build that around `Query.execute/3` itself.

| Need | Before (0.17.0) | After |
|---|---|---|
| Start without blocking | Wrap `Query.execute/3` in a `Task` | `start/3` returns a handle once the child is spawned |
| Progress | `:session_observer` and `:rate_limit_observer` messages only; no frames | Frames forwarded to the owner as they arrive; `snapshot/1` returns status, session id, frame count, last rate-limit observation and elapsed time |
| Wait | `Query.execute/3` returns at the end | `await/2` returns the outcome and the `%ExecutionEvidence{}`; an `await/2` timeout leaves the run going |
| Cancel | End the calling process (child cleanup depends on the runner) | `cancel/2` stops the run through the runner and returns its evidence, with the cancellation recorded |

## API sketch

```elixir
{:ok, run} = ClaudeWrapper.Run.start(query, config, events_to: self())

%{status: :running, session_id: sid, frames: n} = ClaudeWrapper.Run.snapshot(run)

case ClaudeWrapper.Run.await(run, 300_000) do
  {:ok, %ClaudeWrapper.Result{} = result, %ClaudeWrapper.ExecutionEvidence{}} -> result
  {:error, %ClaudeWrapper.Error{} = error, %ClaudeWrapper.ExecutionEvidence{}} -> error
  :timeout -> ClaudeWrapper.Run.cancel(run)
end
```

## Acceptance

- [ ] `start/3` applies the same option validation as `Query.execute/3` and returns rejections before spawning.
- [ ] Frames reach the owner in stream order; the docs state the mailbox policy for a slow owner.
- [ ] `snapshot/1` does not block on the child.
- [ ] `await/2` returns the same `Result` and `Error` categories as `Query.execute/3` plus exactly one evidence record; its timeout does not cancel the run.
- [ ] `cancel/2` is idempotent, records the cancellation in the evidence, and reports the runner's cleanup facts.
- [ ] Owner exit cancels the run.
- [ ] Fake-executable tests for success, failure, timeout, cancel before and after output, and owner exit.

## Related

- #285 (evidenced one-shot execution)
- #314 ("feat(stream): accept execution_observer and runner options on streaming runs") (filed with this batch)
- #323 ("feat(duplex): cancel or release a turn when the send/3 caller times out or exits") (filed with this batch)
- joshrotenberg/forcola#93 (interrupt-first signal sequence)

# Diff of the two new commits (6c0650d..77a00f3)

The diff of PR #351 from 6c0650d to 77a00f3 was included here.

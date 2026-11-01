You are reviewing a change to claude_wrapper, an Elixir wrapper for the Claude Code CLI, in an open pull request; it is already committed . The current directory is the worktree with the change applied. You can read any file. You cannot run commands; the operator runs the checks.

Review the change against the issue below. Report:
1. For each acceptance item: met, not met, or not verifiable by reading, with the file and line that shows it.
2. Defects: incorrect behaviour, races, missing cases, inconsistencies with the surrounding code's conventions, doc claims the code does not support. For each, file:line, what is wrong, and a concrete fix.
3. Anything in the diff that the issue did not ask for, and whether it should stay.
4. A verdict on the last line: APPROVE or REQUEST CHANGES.

Report only what you can point to in the code. Before calling code dead or unused, search the whole repository, including extensions and tests. Do not restate the change.


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

# Diff of PR #351

The diff of PR #351 at that point was included here.

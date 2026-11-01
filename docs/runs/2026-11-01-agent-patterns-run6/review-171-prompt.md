You are reviewing a change to codex_wrapper, an Elixir wrapper for the Codex CLI, in an open pull request; it is already committed. The current directory is the worktree with the change applied. You can read any file. You cannot run commands; the operator runs the checks.

Review the change against the issue below. Report:
1. For each acceptance item: met, not met, or not verifiable by reading, with the file and line that shows it.
2. Defects: incorrect behaviour, races, missing cases, inconsistencies with the surrounding code's conventions, doc claims the code does not support. For each, file:line, what is wrong, and a concrete fix.
3. Anything in the diff that the issue did not ask for, and whether it should stay.
4. A verdict on the last line: APPROVE or REQUEST CHANGES.

Report only what you can point to in the code. Before calling code dead or unused, search the whole repository, including extensions and tests. Do not restate the change.


# Issue #150
## feat: typed turn results with status, final message, thread id and usage

A caller of `Exec.execute/2`, `ExecResume.execute/2`, `Review.execute/2` or `Session.send/3` gets a `%Result{}` with `stdout`, `stderr`, `exit_code` and `success` (`result.ex:10-22`). Everything else codex reports in `--json` output has to be parsed out of `stdout` by the caller. Versions: codex_wrapper 0.8.1 (`7f472e6`), codex-cli 0.165.0.

| Need | Before (0.8.1) | After |
|---|---|---|
| Know a turn failed | `execute/2` returns `{:ok, %Result{success: false}}` on a nonzero exit, while the `exec/2` and `review/1` docs say `{:error, reason}` (`codex_wrapper.ex:95`, `:189`). `turn.failed` is seen only by walking events, which `Structured.decode/2` does for JSON answers. | `status` (`:completed`, `:failed`, `:no_terminal`) and `error`, by the rules `Structured` already uses |
| Final agent message | Parse `stdout` for the last `agent_message`; `Structured.decode/2` does this but fails unless the text is JSON | `final_message`: the last `agent_message` text of the last turn |
| Thread id | Only from `Session` and `ExecFork.fork/2` | `thread_id` from `thread.started` |
| Token usage | Not read anywhere in `lib` (no match for `input_tokens`) | `usage` with `input_tokens`, `cached_input_tokens`, `cache_write_input_tokens`, `output_tokens` and `reasoning_output_tokens`, `nil` when absent; `Session.total_usage/1` |

Usage field names: the codex-cli 0.165.0 binary lists the five fields above next to its `--json` event names. The repo's synthetic fixture (`test/fixtures/fake_codex_structured:32`, after `@openai/codex-sdk` 0.164.0) has `input_tokens`, `cached_input_tokens` and `output_tokens`.

```elixir
{:ok, result} = CodexWrapper.Exec.execute(CodexWrapper.Exec.json(exec), config)
turn = CodexWrapper.Turn.from_result(result)   # pure; starts no process

turn.status         #=> :completed | :failed | :no_terminal
turn.exit_code      #=> 0
turn.thread_id      #=> "019b1e96-6935-7a02-a61e-325504b0b832"
turn.final_message  #=> "done"
turn.usage          #=> %{input_tokens: 120, cached_input_tokens: 100, cache_write_input_tokens: nil,
                    #     output_tokens: 7, reasoning_output_tokens: 3}
turn.error          #=> nil | %{"message" => "..."}
turn.events         #=> [%CodexWrapper.JsonLineEvent{}, ...]
```

## Acceptance

- [ ] A pure projection (name open, `Turn.from_result/1` above) from a `--json` `%Result{}`; `%Result{}` itself is unchanged.
- [ ] Status follows `Structured`: the last `turn.completed` or `turn.failed` decides, a top-level `error` fails the turn only when no terminal event follows, and a nonzero exit is `:failed` even after `turn.completed`.
- [ ] `usage` keeps nonnegative integers only; other fields stay in the raw event.
- [ ] `Session.send/3` exposes the typed turn and `Session.total_usage/1` sums usage across turns.
- [ ] `Structured` and the evidenced `parsed_result` path share the projection.
- [ ] The `exec/2` and `review/1` docs state what a nonzero exit returns.
- [ ] Fixtures for the 0.165.0 usage shape, each marked synthetic or captured.

## Related

- #148 ("fix(session): Session.send reports a failed turn as success") and #151 ("fix(session)!: total_cost/1 returns 0.0 though codex reports no cost").
- #152 ("feat: classify capacity and rate-limit failures, and let Retry retry them").
- #132 (closed): structured output helpers. #116 (closed): native thread identity. #127 (closed): evidenced execution.

# Diff of PR #171

The diff of PR #171 at that point was included here.

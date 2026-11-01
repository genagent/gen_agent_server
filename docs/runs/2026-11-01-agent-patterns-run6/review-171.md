I found no defects that change behaviour. The PR meets all seven acceptance items. There are three small issues: one line that may fail the format check, one inconsistency inside `Turn`, and some repeated re-parsing in `total_usage/1`.

## 1. Acceptance items

| Item | Verdict | Evidence |
|---|---|---|
| Pure projection; `%Result{}` unchanged | Met | `lib/codex_wrapper/turn.ex:78-82` only parses stdout and starts no process. `lib/codex_wrapper/result.ex:10-22` is untouched. `test/codex_wrapper/turn_test.exs:49` checks that the raw result is unchanged. |
| Status rules | Met | The last terminal event decides (`turn.ex:116-132`). A top-level `error` sets `:failed`, and a later terminal event overrides it (`turn.ex:134-135`). A nonzero exit overrides everything (`turn.ex:93-95`). The test table at `turn_test.exs:57-72` covers each ordering. |
| Usage keeps only nonnegative integers | Met | `turn.ex:142-149`. Raw values stay in `terminal_event.data` (`turn_test.exs:142-147`). |
| `Session.send/3` exposes the turn; `total_usage/1` | Met | The updated session carries `last_turn: turn` (`session.ex:125-130`) and `last_turn/1` reads it (`session.ex:216-217`). `total_usage/1` is at `session.ex:204-208`. The typed turn is on the returned session, not in the return tuple, so `send/3`'s return value keeps its shape. |
| `Structured` and `parsed_result` share the projection | Met | `structured.ex:136-137` and `:181-195`; `evidenced_execution.ex:388-404` via `Turn.from_events/1` and `terminal_event`. |
| `exec/2` and `review/1` docs state what a nonzero exit returns | Met | `lib/codex_wrapper.ex:95-98` and `:207-210`. |
| 0.165.0 fixtures marked synthetic or captured | Met | `test/fixtures/turns/README.md:3` marks both fixtures synthetic and names their sources. |

## 2. Defects

1. **`lib/codex_wrapper/structured.ex:187` may fail `mix format --check-formatted`.** By my count the line is 99 characters, and the default `line_length` is 98 (`.formatter.exs` doesn't override it). Fix: run `mix format`, or bind `failed? = match?(...)` first and test `turn.error != nil or failed?`.

2. **`turn.ex:103-104`: `turn.started` resets only part of the state.** It clears `final_message` and `usage`, but not `status`, `error` or `terminal_event`. So for the events `[turn.started, turn.completed(usage), turn.started]`, the result is:
   - `status: :completed`
   - `usage: nil`
   - `terminal_event` still holding the previous turn's usage

   The status matches what `Structured` did before, so this is not a regression. But one struct now describes two different turns. Fix: either document at `turn.ex:13-21` that `status`, `error` and `terminal_event` span the whole stream while `usage` and `final_message` are per-turn, or stop resetting `usage` on `turn.started` and take it from `terminal_event`. Add a test for whichever you choose.

3. **`session.ex:204-207`: `total_usage/1` re-parses every turn's stdout on every call.** Through `SessionServer.total_usage/1` that work happens inside the GenServer call, and each stdout can be up to 1 MiB. Fix: store a per-turn usage list or a running total in `send/3` (`session.ex:125-130`) and sum that instead.

4. **`structured.ex:181-190` changes what callers get back.** The events `[turn.completed, error]` used to decode as `:ok` and now return `{:turn_failed, ...}`. With a nonzero exit, `[turn.completed, error]` used to return `:process_failed` and now returns `:turn_failed`. The new behaviour matches the module's own doc (`structured.ex:35-36`) and the acceptance wording, so it is a fix. Callers will see different results, though, so say so in the PR body or commit message. `structured_test.exs:182-183` covers both cases.

## 3. Changes the issue didn't ask for

- **`SessionServer.last_turn/1` and `total_usage/1`** (`session_server.ex:121-137`, `:197-203`): they mirror the `Session` API the way the existing `total_cost/1` wrapper does. Keep.
- **`Turn.terminal_event`** (`turn.ex:57`): the shared `parsed_result` path needs it. Keep.
- **`parsed_result` now reads the final bounded stdout** instead of a value accumulated while streaming (`evidenced_execution.ex:353`, `:371`). This fixes a stale terminal event surviving after the final output replaced it, and `evidenced_execution_test.exs:319-329` tests it. Keep.
- **`extract_session_id/1` now delegates to `Turn`** (`session.ex:351`). It keeps the same first-nonblank-string rule and its other callers (`exec_fork.ex:423`, `integration_test.exs:43`). Keep.
- **`detail.turn` in `Structured` results** (`structured.ex:76`): an additive key, already allowed by `optional(atom())`. Keep.

APPROVE

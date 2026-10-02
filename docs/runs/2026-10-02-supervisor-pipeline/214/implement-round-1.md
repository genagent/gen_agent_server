I made the change, but I couldn't run `mix format` or `mix test` because the sandbox denied approval for both. The new tests have not been run.

Files changed (all under `extensions/ensemble/`):

- `lib/gen_agent_ensemble/strategies/supervisor.ex`:
  - **New option:** `:max_subtasks` defaults to 10 and is documented in the moduledoc.
  - **Init check:** init raises `ArgumentError` for any non-positive-integer value, matching how Consensus validates options.
  - **Over-limit decompositions:** `decompose/3` counts the decomposer's result before building any ops. If it exceeds the limit, the run returns `{:reply_error, token, {:too_many_subtasks, count, max}}`, starts no workers, and doesn't truncate. It resets to idle and goes through `maybe_prepend_next`, so queued work continues.
- `test/gen_agent_ensemble/strategies/supervisor_test.exs`: new tests for:
  - at the limit
  - over the limit (no workers started, phase back to idle)
  - the default limit (11 sub-prompts rejected)
  - an empty decomposition with `max_subtasks: 1`
  - invalid values (`0`, `-1`, `1.5`, `"3"`, `nil`)
  - a queued run completing after an over-limit run

  I also added an `await_result/3` helper.
- `guides/workflows/supervisor.md`: the start example now sets `max_subtasks: 5`, the "Worker count" bullet states the bound and default, and a new gotcha describes the over-limit error.

Please run `mix format` and `mix test test/gen_agent_ensemble/strategies/supervisor_test.exs` in `extensions/ensemble`. I didn't touch the Ensemble server or main module files that draft #342 is changing.
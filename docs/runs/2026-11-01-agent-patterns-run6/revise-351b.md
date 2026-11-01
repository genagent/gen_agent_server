Follow-up on your PR #351. A second independent review of 77a00f3 approved it with five minor items, quoted below. The operator checked each against the code. Fix all five in one commit (conventional prefix, for example  or  as fits). For item 3, prefer reusing Query's builder through a  function so the two cannot drift. For item 4, make the test independent of scheduling, for example with a larger cancel grace.

## 2. Defects (all minor)

1. **`error.ex:52` is an over-long line that `mix format` won't reflow.** It is the same problem item 7 was about. Fix: rewrap lines 51-54 by hand.
2. **The `:cancelled` entry at `error.ex:42-44` is now incomplete.** It lists only `cancel/2` and owner exit. As of `run.ex:451-452`, a non-`:normal` exit signal also produces `:cancelled`. Fix: add "or by a non-normal exit signal to the run process".
3. **`send_not_started` (`run.ex:289-297`) rebuilds the evidence record by hand instead of using Query's version (`query.ex:1388-1404`).** It leaves out `result:`. That is harmless here, because the stdout is empty and the result is nil. But the two copies can drift apart. Fix: expose a `@doc false` `Query.send_not_started/3` (or reuse `reject_not_started/3`) and call it from `Run`.
4. **The test at `run_test.exs:227` depends on timing.** The 300 ms cancel grace starts when the cancel is requested. If the test process is slow to send `:go` after `wait_until`, the grace kills the worker before the runner returns. The outcome then becomes `:cancelled` and the test fails. Fix: use a larger `cancel_grace_ms` (for example 2_000), so the gap that matters is the telemetry block, not scheduling between the cancel and `:go`.
5. **`run.ex:87` is a short ragged line left over from the doc edit.** This is cosmetic. Fix: reflow the paragraph.


Your environment has MIX_QUIET=1 inherited from the server; unset it when running the test suite so the mix-task tests behave as in CI. Run every CI check locally before pushing, push normally (no history rewrite), wait for CI, update the PR body, keep it ready, and do not merge. No self-started review this time. Same rules for identity, trailers, prose and cleanup. Report the commit, checks and CI status, and how each item was resolved.

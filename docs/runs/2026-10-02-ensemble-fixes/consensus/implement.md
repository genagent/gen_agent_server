I fixed all three findings. I did not run tests or the formatter, as instructed. The `Event.new(:error, %{reason: ...})` gating helper assumes the strategy reports the reason unchanged, as it does for the existing `{:error, reason}` scripts. I have not confirmed that.

Files changed (this pass):
- `extensions/ensemble/lib/gen_agent_ensemble/strategies/consensus.ex`
- `extensions/ensemble/test/gen_agent_ensemble/strategies/consensus_test.exs`

- **P1, round-reset test unreachable:** fixed. The test now uses `{:at_least, 1}`, so round 1 is a reachable tie. Agent `a` errors, `b` approves and `c` rejects, and round 2 reaches consensus. The assertion now expects `via at_least 1, round 2`.
- **P2, last error returned instead of first:** fixed. `record/4` now uses `hd(state.errors)`, which is the first error because errors are appended in order. The two-error test now asserts exactly `{:error, {"a", :first}}`.
- **P2, nondeterministic ordering and queue tests:** fixed. I added `gated/2`, `gated_error/2`, `gated_say/2`, `release/1` and `wait_responded/2` helpers. Each gated script blocks until the test releases it, and `wait_responded` polls `status/1`.
  - The late-error, first-error, later-response-impossible and round-reset tests now release events in a fixed order after confirming progress through `status`.
  - The queued-run test waits for the first run to reach its gate, queues the second run, asserts `queued == 1`, then releases.
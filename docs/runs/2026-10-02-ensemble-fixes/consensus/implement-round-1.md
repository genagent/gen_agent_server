I changed Consensus so a tied threshold no longer reports an arbitrary verdict, and a single turn error no longer aborts a round that can still reach the threshold. I did not run anything: no tests, `mix format` or `mix compile`, because the shell blocked them. Please run them. Two things in the new tests are unchecked. `await/3` is delegated to `Server.await`, and I did not confirm that it returns `{:error, reason}` for a failed token. The error-after-votes test also does not control arrival order.

**Files changed**
- `extensions/ensemble/lib/gen_agent_ensemble/strategies/consensus.ex`
  - **Ties:** `check_threshold/2` now converges only on a unique leading verdict that meets the threshold. A tie goes to re-prompt, or to divergence at the round cap. Unequal counts above a low threshold still converge on the leader.
  - **Tolerated errors:** a turn error is recorded as an abstain for the round, with a `nil` verdict, a rationale of `"turn error: <reason>"` and empty raw text. The reply tuple shapes are unchanged. Late errors from an agent that already answered are ignored.
  - **Reachability:** after every response or error, if errors exist and the largest vote count plus the outstanding turns is below the required votes, the token fails. The required votes use the fixed panel size: N for `:unanimous`, `div(N, 2) + 1` for `:majority`, and `n` for `{:at_least, n}`. The failure uses the first original `{agent, reason}` of the round. `:unanimous` still fails on the first error.
  - **Reset:** a new `errors` field is cleared on finalize, failure, cancel and queued start. A re-prompted round also starts clean, and the failed agent is dispatched again.
  - **Docs:** the moduledoc now describes unique-leader convergence and the new failure semantics.
- `extensions/ensemble/guides/workflows/consensus.md`
  - Added the unique-leader rule under `:threshold`.
  - Added a gotcha on tolerated turn errors and the explicit failure when the threshold is impossible.
- `extensions/ensemble/test/gen_agent_ensemble/strategies/consensus_test.exs`
  - **Ties:** 2-2 `{:at_least, 2}` diverges, with the same result when the agent list is reordered. A tie that resolves in round 2, and unequal counts converging on the leader, are covered.
  - **Errors:** one and multiple tolerated errors, an error arriving after the votes, impossibility found by an error and by a later response, and preservation of the original error.
  - **Reset and shape:** the next queued run after a failure, round-local reset with the agent re-dispatched, and the custom synthesis tuple shape.
  - The existing unanimous error test is kept.

I did not touch the shared server, the other strategies, the version files or git state.
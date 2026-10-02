I couldn't run the new tests. Every `mix test` call needed approval, which this session can't give. So the guide edits and the rewritten scenario test have never been executed.

The two functions the test calls (`GenAgent.runtime_snapshot/1` and `GenAgent.whereis/1`) do exist in `lib/gen_agent.ex`. The test also relies on `status/1` reporting `:processing`, and on `runtime_snapshot(name).pending_notifications` counting queued reviews. I did not check either against source, so those two could fail on first run. Please run:

`mix test test/scenarios/checkpointer_scenario_test.exs test/guides`

Plus the usual `mix format --check-formatted`, `mix credo` and `mix test` for the full suite. I made no changes to `lib/`.

Files changed:

- `guides/patterns/checkpointer.md`
  - Review events are now `{:review, token, decision}`. Each successful draft gets a fresh `review_token` (via `make_ref()`). A decision applies only if its token matches the current one, and the token is cleared on acceptance. Queued, early, stale and duplicate reviews fall through to the catch-all clause.
  - Added `pre_turn/2`, which records the prompt in flight, and `handle_error/3`, which enters a `:failed` phase. That phase holds `failure: %{ref, reason, prompt}` and no review token.
  - Added `{:retry, failure_ref}`, which redispatches the failed prompt only if the ref matches the current failure.
  - Rewrote the prose to explain why tokens are needed, the usage example (it now takes the token from the inspected draft and handles both `:awaiting_review` and `:failed`), and the multi-reviewer variation.
- `test/scenarios/checkpointer_scenario_test.exs`
  - The test now compiles `Checkpointer.Agent` straight from the guide's code block, the same way `test/guides/pool_test.exs` does. It no longer carries a separate agent protocol.
  - It uses a local backend whose turns block until the test replies, so reviews can be sent mid-turn.
  - It keeps the approve, revise and finish happy paths. Reviews with no token or a made-up token are ignored.
  - A review sent while a turn is in flight is not applied to the unseen draft, and a duplicate approve during the next turn does not advance another step.
  - Two approvals queued together advance one step, and the old token is rejected after a revision.
  - A failed first, approval and revision turn each reach `:failed` and recover by retry with the same prompt. A stale or made-up retry is ignored.
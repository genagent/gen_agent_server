I fixed both findings, but I haven't run anything. The shell blocked my format and test commands, and the reviewer saw the dependencies missing, so `mix format --check-formatted` and `mix test` still need a run.

Files changed: `extensions/ensemble/test/gen_agent_ensemble/strategies/supervisor_test.exs` (the only file edited this round).

- **P1, existing tests conflict with the new default:** fixed. The three 12-subtask ordering tests now pass `max_subtasks: 12`.
- **P2, nondeterministic queue test:** fixed. The test now calls the strategy callbacks directly:
  - It does `init`, `handle_tell` for the first run, then `handle_tell` for a second run that queues.
  - It then calls `handle_response` with a 3-item decomposition against a limit of 2.
  - It asserts the ops are exactly `[{:reply_error, :t1, {:too_many_subtasks, 3, 2}}, {:dispatch, "coord", "second", :t2}]` and that the phase is `{:decomposing, :t2}`.
  - I removed `await_result/3` because nothing else used it.
- **Formatter failure at test line 186:** fixed by hand. I wrapped the `assert` line the way `mix format` would.
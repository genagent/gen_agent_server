I’ll check the current docs and tests against the server’s callback, checkpoint, and crash paths without changing files.

The table matches the callback call sites, and the checkpoint paragraph correctly distinguishes returned task results from crashes. I’m checking the test coverage now, especially whether the gates prove blocking and whether any named API is left untested.

REQUEST CHANGES

- **[P2] Incomplete coverage of explicitly named blocking calls — `test/gen_agent/hook_blocking_test.exs:59`, `:87`.** Neither test exercises `poll/3`; the `pre_turn/2` test also omits `tell/3` and `notify_ack/3`. Acceptance requires tests for each case. Add these calls while the hooks are gated, assert they remain pending, then verify their results after release.

The callback table and corrected checkpoint/crash wording match the server implementation. The gates establish hook entry in the agent process; no blocking fragility issue found. Scope is appropriate.

Read-only review; `git diff --check` passed. I did not rerun host validation.
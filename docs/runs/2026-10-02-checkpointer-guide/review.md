I’ll read the changed files and trace notification deferral and turn completion in the runtime, then check the tests for correctness and scope.


The runtime confirms both test assumptions: `status/1` reports `:processing`, and `runtime_snapshot/1` counts deferred notifications. It also stores the response callback’s state before draining those notifications, so a queued review encounters the new draft’s token. I’m checking failure recovery and test synchronization next.


APPROVE

No blocking findings.

- `guides/patterns/checkpointer.md:121`: Fresh tokens and token consumption prevent early, stale, and duplicate reviews from advancing unseen drafts.
- `guides/patterns/checkpointer.md:136`: Failures become visible and recoverable through a failure-specific retry.
- `test/scenarios/checkpointer_scenario_test.exs:1`: Tests execute the guide’s actual module and cover the requested cases.

Verified core notification deferral, transition ordering, and test API assumptions. Changes stay within scope. `git diff --check` passes; tests and host checks were not run.
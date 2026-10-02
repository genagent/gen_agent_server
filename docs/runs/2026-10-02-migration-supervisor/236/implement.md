I’ll verify the overload path, add the failure clause and regression test, then run the focused tests and format/diff checks. I’ll preserve the rest of the uncommitted changes.


The finding holds: a full queue rejects synthesis before `pre_turn/2`, and the error falls through without finishing the run. I’ll make that error fail the run and trigger cleanup. The regression test will also check that halting cancels the queued extra turn.


Fixed — synthesis queue overload now transitions to `:failed` and cleans up workers and watcher. Added the deterministic regression test and updated the boundary paragraph.

Files changed this revision:
- [supervisor.md](/private/tmp/gen_agent_issue_236_supervisor/guides/patterns/supervisor.md)
- [supervisor_test.exs](/private/tmp/gen_agent_issue_236_supervisor/test/guides/supervisor_test.exs)

All 19 focused tests passed, preserving the previous 18. Format and diff checks passed. Tests emitted telemetry availability warnings.

Other changes preserved; no commits, branches, pushes, or network commands.
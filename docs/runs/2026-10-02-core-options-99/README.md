# Core runtime option validation (#99)

The issue covered two startup validation bugs in GenAgent core: an invalid watchdog value crashes the first turn, while an invalid `max_tell_results` value can disable cache pruning. Work ran in an isolated core checkout at `3cd79d7`, leaving the existing `chore/core-refresh` checkout untouched. [Core PR #370](https://github.com/genagent/gen_agent/pull/370) contains the tested fix.

One named `GenAgentServer` Switchboard instance, `handoff/3266`, ran with `max_in_flight: 1`. The exact [control code](issue_handoff_used.exs), [JSON spec](config.json), [issue text](issue.md), and [caller constraints](instructions.md) reconstruct the stage prompts. The script retained [triage](triage.md), [implementation](implement.md), [review](review.md), the initial [diff](diff.patch), per-stage metadata, and [summary](summary.json), then stopped the instance in `after`. Provider session IDs are omitted from the public metadata.

| Stage | Provider / requested model | Actual model | Permissions | Result |
| --- | --- | --- | --- | --- |
| Triage | Codex / CLI default | `gpt-6-astra` | Read-only | Confirmed both bugs; noted the existing `KeyError` contract for missing required keys |
| Implement | Claude / `sonnet` | `claude-sonnet-5-5` | Accept edits in isolated core clone | Added validators, tests, and docs; could not run Mix because dependencies were absent |
| Review | Codex / CLI default | `gpt-6-astra` | Read-only | `REQUEST CHANGES`: implementation asserted the wrong startup error shape and used a sleep to test cache eviction |

The caller corrected both review findings: tests now expect the existing `{:init_failed, :error, ArgumentError}` startup result and wait for explicit turn-completion messages before polling. The final commit differs from the retained initial diff in those two places. Independently, the caller fetched locked dependencies and ran 331 core tests, strict Credo, format, docs, and `git diff --check`; all passed locally. The PR's GitHub checks are the merge gate.

This run illustrates why the control layer should store a review verdict, its concrete findings, a subsequent revision, and host validation as separate evidence. A first implementation with a complete-looking diff was not ready to merge, while the server's staged result was useful for catching the contract error before publication. The server did not commit, push, open, or merge the PR.

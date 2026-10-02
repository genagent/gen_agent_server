# Codex cumulative usage fix (#124)

Codex CLI 0.157.1 reports `turn.completed.usage` as a running thread total. A read-only live [two-turn probe](live_usage_probe.py) on one thread measured input totals `14,985 → 31,279` and output totals `5 → 11`; the [sanitized summary](live_usage_summary.json) retains all five counters without a session ID or provider transcript. The first resume attempt failed because `--skip-git-repo-check` was missing outside a Git checkout; the corrected probe reused the saved first-turn evidence and completed. The recorded CLI fixture independently has input totals `14,956 → 29,938`. Raw probe JSONL remains local and is not published.

[Adapter PR #371](https://github.com/genagent/gen_agent/pull/371) reports increases since the previous completed total and retains all five CLI counters. An externally resumed thread with no baseline does not claim its first reported total as a turn value. Missing or decreasing fields are omitted and rebaselined. Failed or interrupted attempts can contribute to the next completed delta because the CLI only supplies totals on completion.

One named `GenAgentServer` Switchboard instance, `handoff/6277`, ran with `max_in_flight: 1` against an isolated core checkout at `b3173fe`. The exact [control code](issue_handoff_used.exs), [JSON spec](config.json), [issue text](issue.md), and [caller constraints](instructions.md) reconstruct the stage prompts. The script retained [triage](triage.md), [implementation](implement.md), [review](review.md), initial [diff](diff.patch), per-stage metadata, and [summary](summary.json), then stopped the instance in `after`. Provider session IDs are omitted from the public metadata.

| Stage | Provider / requested model | Actual model | Permissions | Result |
| --- | --- | --- | --- | --- |
| Triage | Codex / CLI default | `gpt-6-astra` | Read-only | Confirmed cumulative totals, dropped fields, and unknown-baseline edge case |
| Implement | Claude / `sonnet` | `claude-sonnet-5-5` | Accept edits in isolated adapter clone | Implemented session baseline, translator deltas, tests, and docs; Mix checks were unavailable inside the worker |
| Review | Codex / CLI default | `gpt-6-astra` | Read-only | `REQUEST CHANGES`: a no-usage test contradicted its own empty-total implementation |

The caller fixed that assertion, then ran the full adapter suite. It found a second stale cumulative expectation in the recorded executable-conformance test, which was changed to assert the explicit `14,982` input-token delta. The final commit differs from the initial diff at those two test sites. The caller independently passed 96 adapter tests (three opt-in live tests excluded), strict Credo, format, docs, and diff checks. GitHub PR CI is the merge gate.

This run adds two control lessons: a read-only live probe can settle an uncertain provider contract before implementation, and recorded fixtures need separate expectations for raw CLI totals and normalized adapter results. A review verdict and host test findings each produced a distinct revision. The server did not commit, push, open, or merge the source PR.

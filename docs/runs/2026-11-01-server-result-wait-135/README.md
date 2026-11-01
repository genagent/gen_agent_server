# gen_agent_server result wait (#135)

Second run of [working-an-issue.md](../../working-an-issue.md). The step
moved to agents this time was the first pass of verification: a Claude
read-only route reviewed the Codex implementation before the operator's host
checks. The issue came from the first run's friction log; the change is
[gen_agent_server#136](https://github.com/genagent/gen_agent_server/pull/136).

| Item | Value |
| --- | --- |
| Server | `dfc4c75`, the same release as run 1 |
| Target | gen_agent_server `dfc4c75`, worktree on `feat/result-wait-135` |
| Providers | codex-cli 0.165.0 (`workspace_write`); Claude Code 2.1.316 (`read_only`) |
| Instances | `gen_agent_server-135` (route `impl`) and `gen_agent_server-135-review` (route `review`) ([config](config.json)) |

## Turns

| Turn | Route | Prompt | Duration | Result |
| --- | --- | --- | --- | --- |
| Implement | Codex `impl` | [issue plus constraints](implement-prompt.md) | 160 s | [Report](implement.md): all seven acceptance items, 11 files ([diff](implement.diff)) |
| Review | Claude `review` | [acceptance table, defects, verdict](review-prompt.md) with the diff inline | 101 s | [REQUEST CHANGES](review.md): five defects |
| Revise | Codex `impl`, same session | [review text plus one operator correction](revise-prompt.md) | 56 s | [Report](revise.md): five fixes with regression tests ([final diff](final.diff)) |

## Review against the operator

Before the review ran, the operator had read the core diff and noted two
points. The review found both (CLI message for `:invalid_wait`; unvalidated
options) and three the operator had missed:

- the shared HTTP MCP listener exposes the new 600 s wait with a 10 s request
  timeout and eight request slots;
- the catalogue schema has no maximum for `wait_ms`;
- wait expiry replies pending without draining the inbox, so a turn that
  finished since the last poll is reported pending.

One review claim was wrong: it called the two-element `{:result, id}` clause
dead code, but the control extension's tests send it. The operator checked
that with one grep and corrected it in the revision prompt.

## Host checks

After each Codex turn: warnings-as-errors compile, format, root tests (124,
then 127; 118 before), the examples script, the echo smoke, a prod release,
and every extension. The agent reported 7 root failures and sandbox failures
in mcp, patterns and peers; none occur on the host.

The first CI run failed one control test
(`controller_timing_test.exs:198`): its helper monitors a process after
reading its pid from state, and gets `:noproc` when the process has already
exited. It passed in 8 local runs, including with the CI seed, and on the
rerun. It is an existing race, not part of this change.

## Scorecard

| Step | Run 1 | Run 2 |
| --- | --- | --- |
| 1 Server | operator | operator (reused) |
| 2 Issue | operator | operator |
| 3 Worktree | operator | operator, plus dependencies for seven extensions |
| 4 Draft PR | operator | operator |
| 5 Instance | operator | operator |
| 6 Prompt | operator | operator |
| 7 Implement | agent | agent |
| 8 Verify | operator | agent review, then operator host checks |
| 9 Revise | agent, operator-written prompt | agent, review forwarded with one correction |
| 10 Commit, PR | operator | operator |
| 11 Record | operator | operator |

## Observations

| Observation | Class | Response |
| --- | --- | --- |
| A second provider's read-only review found three defects the operator missed and one false claim. | Behavioural | Keep a review route; the operator checks review claims before forwarding. |
| The Claude `read_only` route cannot run commands, so the diff was pasted into the prompt (22 KB). | Mechanical | Acceptable at this size. |
| gen_agent_server extensions are separate Mix projects; the operator fetched dependencies for seven of them before the run. | Mechanical | Part of step 3 for this repository. |
| The control extension has a timing race in a test helper. | Mechanical | Separate fix in the control extension. |

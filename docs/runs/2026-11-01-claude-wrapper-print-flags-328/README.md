# claude_wrapper print flags (#328)

Third run of [working-an-issue.md](../../working-an-issue.md). Agents took over the PR plan and implementation prompt. The operator forwarded the review without rewording. The change is [claude_wrapper_ex#350](https://github.com/genagent/claude_wrapper_ex/pull/350).

| Item | Value |
| --- | --- |
| Server | `dfc4c75`, the same release as runs 1 and 2 |
| Target | claude_wrapper_ex `49a111d`, worktree on `feat/query-print-flags-328`; baseline 1004 tests |
| Providers | codex-cli 0.165.0 (`read_only`); Claude Code 2.1.316 (`accept_edits`) |
| Instances | `claude_wrapper_ex-328`, routes `triage` (Codex), `impl` (Claude), `review` (Codex) |
| Artifacts | [Turn summary](summary.json), [final diff](final.diff) |
| Commits | Operator: `3e94a63` feat(query), `04c2ccf` fix(contract); no trailers |

## Turns

| Turn | Route | Prompt | Duration | Result |
| --- | --- | --- | --- | --- |
| Triage | Codex `triage` | [issue and plan constraints](triage-prompt.md) | 79 s | [Plan and prompt](triage.md): checked CLI 2.1.316; corrected unset versus false; imposed an autocompact range later rejected by review |
| Implement | Claude `impl` | [triage prompt](implement-prompt.md) | 488 s | [Report](implement.md): 11 files, 848 lines; all checks blocked by Bash approval |
| Review | Codex `review` | [acceptance and defects](review-prompt.md) | 29 s | [REQUEST CHANGES](review.md): autocompact rejected CLI shorthand such as `200`; Query exceeded the Credo struct-field limit |
| Revise | Claude `impl`, same session | [review forwarded unchanged](revise-prompt.md) | 36 s | [Report](revise.md): accepted positive integers and raised the Credo limit; noted the triage conflict |
| Revise 2 | Claude `impl`, same session | [contract version tagging](revise2-prompt.md) | 72 s | [Report](revise2.md): tagged five flags as checked from 2.1.309; introduced a compile error |
| Revise 3 | Claude `impl`, same session | [Version alias correction](revise3-prompt.md) | 9 s | [Report](revise3.md): qualified `Elixir.Version.compare/2` |

## Host checks

After implementation, all host checks passed except Credo: Query had 64 fields against a limit of 56. After the first revision, all checks passed, including the contract on installed CLI 2.1.316.

The first CI push failed the contract against pinned CLI 2.1.220. Five new flags did not exist there. The operator installed that version and reproduced the failure. The Elixir 1.18 job also timed out at `stream_test.exs:129`; it passed on the next run.

The second revision failed compilation because `Version.compare` resolved to `ClaudeWrapper.Commands.Version`. After the third revision: 1037 tests, Credo clean, no contract drift on 2.1.220 or 2.1.316, and CI 6/6. The implementer ran no checks.

## Scorecard

| Step | Run 1 | Run 2 | Run 3 |
| --- | --- | --- | --- |
| 1 Server | operator | operator (reused) | operator (reused) |
| 2 Issue | operator | operator | operator |
| 3 Worktree | operator | operator, plus dependencies for seven extensions | operator |
| 4 Draft PR | operator | operator | operator, plan by agent |
| 5 Instance | operator | operator | operator |
| 6 Prompt | operator | operator | agent triage |
| 7 Implement | agent | agent | agent |
| 8 Verify | operator | agent review, then operator host checks | agent review, then operator host checks and CI |
| 9 Revise | agent, operator-written prompt | agent, review forwarded with one correction | agent, review forwarded unchanged; operator prompts for CI and compile fixes |
| 10 Commit, PR | operator | operator | operator |
| 11 Record | operator | operator | operator |

## Observations

| Observation | Class | Response |
| --- | --- | --- |
| Claude `accept_edits` could write files but could not run Bash. The implementer never compiled or tested. | Mechanical | Issue #137 addresses the default access gap. |
| Triage imposed an autocompact range that rejected valid CLI shorthand. Review corrected it. | Behavioural | Forwarded the review unchanged; the implementer followed it and reported the conflict. |
| Host checks covered installed CLI 2.1.316 but missed the pinned CI version. | Mechanical | Reproduced on 2.1.220 and added checked-version tags. A gates helper should read the CI workflow. |
| The contract revision called an aliased command module instead of Elixir’s Version module. | Behavioural | Host compilation caught it; a third revision qualified the call. |
| Session snapshot tests checked argv, not the real API request body. | Behavioural | Recorded that limit rather than claiming end-to-end verification. |

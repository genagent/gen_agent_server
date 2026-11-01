# Three agent patterns over the agent call (run 6)

Sixth run of [working-an-issue.md](../../working-an-issue.md). The server was the #140 spike: the agent operation over codex_wrapper 0.9.0 and claude_wrapper 0.19.0, with no GenAgent or Ensemble on the turn path. Three issues ran in parallel, one per pattern: a single-use subagent for codex_wrapper #156, a long-lived counterpart session for codex_wrapper #150, and a recursive session for claude_wrapper #315 that started its own reviewers through the agent call. The operator chose the issues and patterns, wrote one shared rules block and a one-paragraph task per issue, and started each session with one agent call. Agents created worktrees, opened draft PRs, implemented, ran checks, committed, watched CI, and marked PRs ready. The changes are [codex_wrapper_ex#170](https://github.com/genagent/codex_wrapper_ex/pull/170) and [#174](https://github.com/genagent/codex_wrapper_ex/pull/174), [codex_wrapper_ex#171](https://github.com/genagent/codex_wrapper_ex/pull/171) and [#173](https://github.com/genagent/codex_wrapper_ex/pull/173), and [claude_wrapper_ex#351](https://github.com/genagent/claude_wrapper_ex/pull/351).

| Item | Value |
| --- | --- |
| Server | gen_agent_server #140 spike: the agent operation over codex_wrapper 0.9.0 and claude_wrapper 0.19.0, with no GenAgent or Ensemble on the turn path; daemon `gen_agent_server_dogfood@127.0.0.1`, started 2026-11-01T13:36:41Z |
| Targets | codex_wrapper_ex #156 (single-use), codex_wrapper_ex #150 (counterpart), claude_wrapper_ex #315 (recursive); feature worktrees created by the agents |
| Providers | Codex `inherit` for the codex_wrapper sessions; Claude `auto` for the recursive session; Claude `read_only` for the independent reviews; Codex `read_only` for the reviewers the recursive session started |
| Sessions | Single-use: `single-156`, `single-170-revise`, `single-174-footer`. Counterpart: `counterpart-codex-wrapper`, three turns. Recursive: `recursive-315`, two turns, plus self-started `review-315` and `review-351-confirm`. Reviews: `review-170`, `review-171`, `review-351` |
| Artifacts | [Turn summary](summary.json) |
| Commits | #170: `7f00ab7`, `352ffb4`. #174: `a87d02d`, `575ac55`. #171: `7b285df`, `cd602af`. #173: `07acb72`, `00e9d57`. #351: `85ebe46`, `70ece8c`, `5b878ab`, `6c0650d`, `03ed771`, `77a00f3` |
| Cost | Claude reported $22.01 over six turns. Codex reports no cost; its turns are not included |

## Turns

All prompts except the review prompts and the self-started reviewer prompts were written by the operator. The shared rules block is part of each implement prompt.

### Single-use subagent (codex_wrapper #156)

| Turn | Route | Prompt | Duration | Result |
| --- | --- | --- | --- | --- |
| Implement | Codex `inherit`, `single-156` | [issue and repository rules](p-156.md) | 1004 s | [Report](r-156-1.md): PR #170 ready; 736 tests; CI 5/5 |
| Review | Claude `read_only`, `review-170` | [review instructions, issue, and diff](review-170-prompt.md) | 164 s ($2.07) | [REQUEST CHANGES](review-170.md): runner `:env` typedoc wrong for `false` unsets, commit lacks `!`, minor double environment read |
| Cross-review | Codex, `counterpart-codex-wrapper` turn 2 | [read-only review of #170](cross-170.md) | 292 s | [REQUEST CHANGES](r-150-2.md): IEx `@config_keys` omits `:release_env`; no merge conflict with #171 |
| Revise 1 | Codex `inherit`, `single-170-revise`, fresh session | [merged findings of both reviews](revise-170.md) | 434 s | [Report](r-170-revise.md): fixed all three items in local commit `a4cf14f`; found #170 merged; stopped and asked how to deliver |
| Revise 2 | Codex, `single-170-revise`, same session | [follow-up PR from main](revise-170-2.md) | 637 s | [Report](r-170-revise-2.md): PR #174 ready with `a87d02d`, no breaking marker; CI 5/5; removed the merged worktree; noted #170's squash subject has no `!` |
| Revise 3 | Codex, `single-170-revise`, same session | [amend and force push](revise-170-3.md) | 8 ms | [Failed](r-170-revise-3.md): `{:exit, 2, ""}`; the session's cwd had been removed in revise 2 |
| Declare breaking | Codex `inherit`, `single-174-footer`, fresh session | [empty commit with footer](revise-174.md) | 379 s | [Report](r-174.md): `575ac55` with `!` title and `BREAKING CHANGE` footer; CI 5/5 |

### Counterpart session (codex_wrapper #150)

| Turn | Route | Prompt | Duration | Result |
| --- | --- | --- | --- | --- |
| Implement | Codex `inherit`, `counterpart-codex-wrapper` turn 1 | [issue, repository rules, long-lived session](p-150.md) | 994 s | [Report](r-150-1.md): PR #171 ready; 730 tests per runtime; CI 5/5 |
| Review | Claude `read_only`, `review-171` | [review instructions, issue, and diff](review-171-prompt.md) | 128 s ($2.05) | [APPROVE](review-171.md) with three items; one false finding on line length |
| Revise | Codex, same session, turn 3 | [review with one correction](revise-171.md) | 1037 s | [Report](r-150-3.md): found #171 merged; opened PR #173 from the merged branch; 765 tests per runtime; CI 5/5 |

Turn 2 of this session was the cross-review of #170, listed under the single-use pattern.

### Recursive session (claude_wrapper #315)

| Turn | Route | Prompt | Duration | Result |
| --- | --- | --- | --- | --- |
| Implement | Claude `auto`, `recursive-315` turn 1 | [issue, repository rules, self-started review step](p-315.md) | 2539 s ($5.95) | [Report](r-315-1.md): PR #351 ready; 1058 tests; Docker runtimes and CLI contracts; CI green on `6c0650d` |
| Self-started review | Codex `read_only`, `review-315`, started by the implementer | written by the implementer, not retained | not recorded | Two turns, from the implementer's report: REQUEST CHANGES with three defects, then confirmed the fixes and found one defect they introduced. The implementer stopped the session |
| Review | Claude `read_only`, `review-351` | [review instructions, issue, and diff](review-351-prompt.md) | 164 s ($1.85) | [REQUEST CHANGES](review-351.md): seven items, none found by the self-started reviewer |
| Revise | Claude `auto`, same session, turn 2 | [review defects verbatim, confirm through a fresh reviewer](revise-351.md) | 1228 s ($8.43) | [Report](r-315-2.md): fixed six items, documented one; 1065 tests; CI green on `77a00f3` |
| Confirm review | Codex `read_only`, `review-351-confirm`, started by the implementer | written by the implementer, not retained | not recorded | From the implementer's report: confirmed items 1 to 7, found three new defects, REQUEST CHANGES. Fixed in `77a00f3`, which was not reviewed again |

## Verification

Each implementer ran the CI checks locally. The codex_wrapper agents ran both Elixir runtimes and CLI contracts for 0.149.0, 0.164.0, and 0.166.0. The #156 agent also ran eight real-release smoke cases. The recursive agent mirrored CI in Docker for Elixir 1.18/OTP 27 and 1.19/OTP 28, and ran the contract job for claude 2.1.220 and 2.1.309 with the linux-arm64 binary; CI uses x64. It reported 5 mix-task tests failing locally with `MIX_QUIET=1` set and passing without it.

After the first implement turns, the operator checked #170 and #171 with `gh`: commits by Josh, no trailers, CI 5/5, no em dashes in the PR bodies. The agents' chat reports used em dashes in commit lists; GitHub artifacts did not. The operator recorded #351 after turn 1 as CI 6/6, 4 commits by Josh, no trailers, no em dashes. The agent's report says 8 jobs.

The operator recorded #173 with CI 5/5, no trailers, and no em dashes, and #174 with CI 5/5 after `575ac55`. The owner merged #170 at 13:56:44 and #171 at 13:57:17, while the reviews were running. The agents left #173, #174, and #351 ready and unmerged. After recursive turn 2 the operator checked #351: 6 commits by Josh, no trailers, no em dashes, CI 6/6 on `77a00f3`, no containers left.

## Scorecard

| Step | Run 1 | Run 2 | Run 3 | Run 4 | Run 5 | Run 6 single-use | Run 6 counterpart | Run 6 recursive |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 Server | operator | operator (reused) | operator (reused) | operator (reused) | operator, rebuilt from main | operator, #140 spike | operator, #140 spike | operator, #140 spike |
| 2 Issue | operator | operator | operator | operator | operator | operator | operator | operator |
| 3 Worktree | operator | operator, plus dependencies for seven extensions | operator | operator, plus dependencies for seven extensions | agent | agent | agent | agent |
| 4 Draft PR | operator | operator | operator, plan by agent | operator, plan by agent | agent | agent | agent | agent |
| 5 Session | operator | operator | operator | operator | operator | operator, agent call per task; three sessions | operator, one agent call; one session for three turns | operator for the implementer; implementer for its two reviewers |
| 6 Prompt | operator | operator | agent triage | agent triage, reusable template | operator, generic repository rules | operator, shared rules and task paragraph | operator, shared rules and task paragraph | operator, shared rules, task paragraph, and review step; reviewer prompts by the implementer |
| 7 Implement | agent | agent | agent | agent | agent | agent | agent | agent |
| 8 Verify | operator | agent review, then operator host checks | agent review, then operator host checks and CI | agent review, then operator host checks and live probe | agent local checks and CI, independent agent review, operator checks | agent local checks and CI, independent Claude reviewer and the counterpart, operator checks | agent local checks and CI, independent Claude reviewer, operator checks | agent local checks and CI, the implementer's self-started reviewer, then independent Claude reviewer, operator checks |
| 9 Revise | agent, operator-written prompt | agent, review forwarded with one correction | agent, review forwarded unchanged; operator prompts for CI and compile fixes | agent, review forwarded with operator choices for two fixes | agent, review forwarded with directions for breaking-change marking and Docker cleanup | fresh session with both reviews merged; two more turns after the merge; fresh session for the breaking marker | same session, Claude reviewer forwarded with one correction; agent opened #173 itself | same session, its own reviewer, then Claude reviewer forwarded verbatim; confirmed by the implementer's self-started reviewer |
| 10 Commit, PR | operator | operator | operator | operator | agent | agent | agent | agent |
| 11 Record | operator | operator | operator | agent draft, operator check | agent draft, operator check | agent draft, operator check | agent draft, operator check | agent draft, operator check |

## Observations

| Observation | Class | Response |
| --- | --- | --- |
| The owner merged #170 and #171 while their reviews were running. Revisions then found the PRs merged. | Mechanical | #170's fixes went to follow-up PR #174. The counterpart opened #173 on its own. |
| The single-use session for #170 stopped when its prompt forbade a new PR and asked how to deliver. | Behavioural | Correct refusal. The operator sent a second turn to the same session with a follow-up PR instruction. "Single-use" became "single task". |
| The counterpart opened #173 by merging main into the merged branch `feat/150-typed-turn-results`. | Behavioural | Its prompt did not forbid a new PR. The branch keeps #171's commits; squash merge hides them. |
| Revise 2 removed the old worktree, which was the session's cwd. Revise 3 failed in 8 ms. | Mechanical | A session's cwd can disappear under it. The operator moved the work to a fresh session in the new worktree. |
| The cwd failure surfaced as `{:exit, 2, ""}`, with no stderr. | Mechanical | The error does not name the cause. The cause was found from the session's previous turn. |
| Three concurrent `mix gen_agent_server.ops` calls from one checkout contended for the Mix build lock. "Waiting for lock" lines went into the result files. | Mechanical | `wait.sh` now sends stderr to separate files. A standalone binary would not have this. |
| The daemon was started with `MIX_QUIET=1` exported. Sessions inherited it, and 5 claude_wrapper mix-task tests failed locally. | Mechanical | The operator exported it before `daemon`. Restart the daemon without it before the next run. |
| A stopped session leaves no record. `review-315` is absent from `agent_sessions`. | Mechanical | Its turns are known only from the implementer's report. The self-started reviewer prompts were not retained. |
| Claude `inherit` means the user's `settings.json`, not the creator session's mode. Headless, it cannot run Bash. | Mechanical | The recursive session was started with access `auto`. It ran mix, Docker, and gh with no permission denials. Native subagents inherit the creator's mode; the server cannot see it. |
| On #170, the Claude reviewer and the counterpart found disjoint defects. On #351, the Claude reviewer found seven items the self-started Codex reviewer did not. | Behavioural | Findings from both reviewers were merged into one revise prompt. The independent review stays after a self-started review. |
| The Claude reviewer of #171 reported a line-length defect that CI's format check contradicts. | Behavioural | The operator told the counterpart to ignore it unless `mix format` changed the line. It did not. |
| The operator read #170's PR title, `feat(env)!`, which had been changed after the merge. The squash commit `590ef0b` has no `!` and no footer. The instruction to drop the marker on #174 was wrong. | Behavioural | The session's note was right. #174 got an empty commit `575ac55` with a `!` subject and a `BREAKING CHANGE` footer. The owner must keep the `!` title and footer when squash-merging #174. |
| The first replacement prompt asked for amend and force push. The operator's auto-mode safety check blocked it as destructive git. | Mechanical | Reworked to an empty commit and a `!` title, with no history rewrite. |
| The last fix commits, `6c0650d` after turn 1 and `77a00f3` after turn 2, were not reviewed again by the implementer's reviewers. | Behavioural | The operator started review-351 for `6c0650d` and, at the owner's request, [review-351b](review-351b.md) for `77a00f3` (101 s, $1.66): APPROVE, all earlier items resolved, five minor items (two doc gaps, a duplicated evidence builder, a timing-sensitive test, a ragged doc line). The operator confirmed them in the code. |
| An agent drafted this record from artifacts and operator notes. | Behavioural | The operator checks it. |

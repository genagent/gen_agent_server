# gen_agent_server inherit access (#137)

Fourth run of [working-an-issue.md](../../working-an-issue.md). The operator wrote the issue from runs 1 through 3 and a comparison with native subagent tools. Agents produced the plan and implementation prompt, reviewed the change, and drafted this record. The change is [gen_agent_server#138](https://github.com/genagent/gen_agent_server/pull/138).

| Item | Value |
| --- | --- |
| Server | `dfc4c75`, the same release as earlier runs |
| Target | gen_agent_server `dfc4c75`, worktree on `feat/inherit-access-137`; baseline 118 tests |
| Providers | Codex (`read_only` triage, `workspace_write` implementation); Claude (`read_only` review) |
| Instances | `gen_agent_server-137`, routes `triage`, `impl`, `review` |
| Artifacts | [Turn summary](summary.json), [final diff](final.diff) |
| Commit | Operator: `aab6a07` feat! |

## Turns

| Turn | Route | Prompt | Duration | Result |
| --- | --- | --- | --- | --- |
| Triage | Codex `triage` | [issue and reusable triage constraints](triage-prompt.md) | 78 s | [Plan and prompt](triage.md): found separate pattern validation, resumed sandbox overrides, control review policy, and the profile `read_only` gap |
| Implement | Codex `impl` | [triage prompt](implement-prompt.md) | 163 s | [Report](implement.md): 18 files; inherited defaults across routes, profiles, startup agents, and patterns |
| Review | Claude `review` | [reusable review constraints](review-prompt.md) | 166 s | [REQUEST CHANGES](review.md): seven defects, including deleted docs, weaker Codex review admission, duplicated allowlists, and startup override behavior |
| Revise | Codex `impl`, same session | [review with operator-selected fixes](revise-prompt.md) | 123 s | [Report](revise.md): addressed all seven; required explicit config ignore for Codex review routes and kept startup construction free of overrides |
| Revise 2 | Codex `impl`, same session | [release smoke assertion](revise2-prompt.md) | 13 s | [Report](revise2.md): the MCP release smoke matched the new quickstart default |

## Host checks

After implementation and revision, all host checks passed. Root tests increased to 125, then 126. All seven extension projects passed. Dependencies had been fetched for the root and extensions before the run.

The agent reported sandbox failures in root CLI assertions, patterns, MCP, and peers. These involved Mix TCP warnings or denied socket access. They did not occur on the host.

The operator built a release from the branch and ran it on a second node. A Codex route with omitted access options and a Claude route with `claude_permission_mode: auto` each ran `git ls-remote` over the network. Both returned the same hash as the host.

CI then failed the mcp job: `examples/mcp_release_smoke.exs` asserted the old quickstart wording (`to a read-only sandbox`). The operator's host checks had not run that step. A second revision changed the assertion, and the release smoke passed on the host.

## Scorecard

| Step | Run 1 | Run 2 | Run 3 | Run 4 |
| --- | --- | --- | --- | --- |
| 1 Server | operator | operator (reused) | operator (reused) | operator (reused) |
| 2 Issue | operator | operator | operator | operator |
| 3 Worktree | operator | operator, plus dependencies for seven extensions | operator | operator, plus dependencies for seven extensions |
| 4 Draft PR | operator | operator | operator, plan by agent | operator, plan by agent |
| 5 Instance | operator | operator | operator | operator |
| 6 Prompt | operator | operator | agent triage | agent triage, reusable template |
| 7 Implement | agent | agent | agent | agent |
| 8 Verify | operator | agent review, then operator host checks | agent review, then operator host checks and CI | agent review, then operator host checks and live probe |
| 9 Revise | agent, operator-written prompt | agent, review forwarded with one correction | agent, review forwarded unchanged; operator prompts for CI and compile fixes | agent, review forwarded with operator choices for two fixes |
| 10 Commit, PR | operator | operator | operator | operator |
| 11 Record | operator | operator | operator | agent draft, operator check |

## Observations

| Observation | Class | Response |
| --- | --- | --- |
| Triage found access validation outside the core provider builder and a different sandbox path for resumed Codex turns. | Behavioural | Included patterns, resume coverage, and control review provenance in the prompt. |
| Review found that explicit Codex `read_only` now inherited user MCP servers. | Behavioural | Required explicit `codex_user_config: ignore` for control review admission. |
| Reusing the provider builder made startup configuration pick up overrides during runtime configuration evaluation. | Behavioural | Added an internal construction path that skips overrides and defers environment hardening. |
| Review found unrelated documentation deletions, repeated access text, copied allowlists, stale names, and missing bypass guidance. | Behavioural | Restored documentation, centralized choices, and corrected the remaining text and tests. |
| The review template now requires a repository-wide search before declaring code dead. | Behavioural | Carried forward the correction from run 2’s false claim. |
| Sandbox checks failed where host checks passed. Live routes successfully reached the network. | Mechanical | Used host checks as authoritative and tested access through a release on a second node. |
| An earlier `ask` from a non-git cwd returned only `no_terminal_event`. The CLI’s error was not surfaced. | Mechanical | Recorded the diagnostic gap separately from the access change. |
| Host checks again did not mirror the CI workflow (the MCP release smoke), as in run 3. | Mechanical | A gates helper that reads `.github/workflows/ci.yml` is now the top helper candidate. |
| An agent drafted this record from artifacts and operator notes. | Behavioural | The operator checks the draft before saving it. |

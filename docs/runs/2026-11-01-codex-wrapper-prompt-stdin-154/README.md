# codex_wrapper prompt on stdin (#154)

Fifth run of [working-an-issue.md](../../working-an-issue.md). The operator selected the issue, created the instance, and wrote a generic prompt with the repository owner's rules. Agents handled the worktree, draft PR, implementation, checks, commits, CI watch, and PR readiness. The change is [codex_wrapper_ex#169](https://github.com/genagent/codex_wrapper_ex/pull/169).

| Item | Value |
| --- | --- |
| Server | Rebuilt from main `395200f`, including #136 wait on result and #138 inherit by default |
| Target | codex_wrapper_ex #154; feature worktree created by the agent |
| Providers | Codex with omitted access options, resolved to `inherit/inherit`; Claude `read_only` review; codex-cli `0.165.0` |
| Instances | Repository instance `codex_wrapper_ex`, route `dev`, cwd the main clone; separate review instance `review-154` |
| Artifacts | [Turn summary](summary.json), [final diff](final.diff) |
| Commit | Agent: `f200c7c`, `63ea405`, `bdb454f`, `1191afb`, `668d032` |

## Turns

| Turn | Route | Prompt | Duration | Result |
| --- | --- | --- | --- | --- |
| Implement 1 | Codex `dev` | [issue and repository rules](prompt.md) | 600 s | Failed with `timeout`; pushed the start commit and opened draft PR #169; left uncommitted edits |
| Implement 2 | Codex `dev` | [continuation with the existing state](prompt2.md) | 1152 s | [Report](implement.md): completed implementation and self-review; 692 tests; CI 5/5; PR ready |
| Review | Claude `read_only` | [diff, PR body, and review constraints](review-prompt.md) | 223 s | [REQUEST CHANGES](review.md): seven defects, including unsafe argument-limit fallback and missing breaking-change marking |
| Revise | Codex `dev`, same session | [review with two operator directions](revise-prompt.md) | 1072 s | [Report](revise.md): fixed all seven and a macOS Bash 3.2 hang introduced by the first fix; 705 tests; CI 5/5; Docker resources removed |

## Verification

The agent ran every CI check locally on macOS and both Linux runtimes in Docker. It reported 692 tests after implementation and 705 after revision. Each suite had zero failures and four integration exclusions. Checks covered dependencies, unused dependencies, Hex audit, strict compilation, formatting, Credo, Dialyzer, tests, and strict docs.

CLI contracts passed for 0.149.0, 0.164.0, and 0.166.0. Version 0.149.0 rejected a field in the user's config. The agent used a temporary config directory for that check.

After turn 2, the operator verified that commits were authored by Josh Rotenberg and had no trailers. The PR body had no em dashes or attribution. All five CI jobs passed. Two Docker containers were still running, and two images remained.

After turn 3, the operator again verified authorship, absent trailers, and CI 5/5. The PR title used `feat!`, and its body opened with `BREAKING CHANGE`. No `codex154` containers or images remained. The PR was ready for review and unmerged.

## Scorecard

| Step | Run 1 | Run 2 | Run 3 | Run 4 | Run 5 |
| --- | --- | --- | --- | --- | --- |
| 1 Server | operator | operator (reused) | operator (reused) | operator (reused) | operator, rebuilt from main |
| 2 Issue | operator | operator | operator | operator | operator |
| 3 Worktree | operator | operator, plus dependencies for seven extensions | operator | operator, plus dependencies for seven extensions | agent |
| 4 Draft PR | operator | operator | operator, plan by agent | operator, plan by agent | agent |
| 5 Instance | operator | operator | operator | operator | operator |
| 6 Prompt | operator | operator | agent triage | agent triage, reusable template | operator, generic repository rules |
| 7 Implement | agent | agent | agent | agent | agent |
| 8 Verify | operator | agent review, then operator host checks | agent review, then operator host checks and CI | agent review, then operator host checks and live probe | agent local checks and CI, independent agent review, operator checks |
| 9 Revise | agent, operator-written prompt | agent, review forwarded with one correction | agent, review forwarded unchanged; operator prompts for CI and compile fixes | agent, review forwarded with operator choices for two fixes | agent, review forwarded with directions for breaking-change marking and Docker cleanup |
| 10 Commit, PR | operator | operator | operator | operator | agent |
| 11 Record | operator | operator | operator | agent draft, operator check | agent draft, operator check |

## Observations

| Observation | Class | Response |
| --- | --- | --- |
| GenAgent's default `watchdog_ms` of 600,000 ended turn 1. The server did not expose the setting. | Mechanical | The operator set trusted `provider_overrides` to `watchdog_ms: :infinity` for Codex, recreated the instance, and confirmed the value on the live agent. |
| Inherited access let the agent complete every step from worktree creation to a ready PR. | Behavioural | Moved worktree creation, draft PR, local checks, commits, CI watch, and readiness to the agent. |
| The agent mirrored the CI matrix, including Linux runtimes and three CLI versions. | Behavioural | The gates helper proposed after runs 3 and 4 was unnecessary for this run. |
| Independent review found seven defects after Codex self-review. The 32 KiB argument-limit fallback could reject valid commands. | Behavioural | Forwarded the review. The agent fixed all seven defects and added regressions. |
| The first launcher fix caused a hang under macOS Bash 3.2. | Mechanical | Full macOS checks caught it. The agent replaced `command exec` with plain `exec` and a temporary EXIT trap, then reran validation. |
| The run's prompt was visible in `ps`. | Mechanical | This PR moves prompts to stdin once released. |
| The agent left Docker containers and images after turn 2. | Behavioural | The operator requested cleanup. The agent removed its Docker resources after final CI passed. |
| An agent drafted this record from artifacts and operator notes. | Behavioural | The operator checked it and removed a preamble line. |

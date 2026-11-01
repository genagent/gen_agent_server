Write the run record for run 6 of gen_agent_server's issue procedure into this worktree (branch docs/issue-process). Create the directory docs/runs/2026-11-01-agent-patterns-run6 and these files in it. Do not commit or push; the operator reviews and commits.

Sources, all in /private/tmp/claude-501/-Users-joshrotenberg--claude-spares-spare-r9MVhC/1bed81a4-3681-4f7b-bd5f-10b23d2c9e65/scratchpad/run-6:
- operator-notes.md: authoritative for what happened and why.
- summary.json: every turn with pattern, session, step, prompt file, status, duration and reported cost.
- The prompt files named in summary.json, and the turn outputs (r-*.json, review-*.json; JSON with a "text" field; some have Mix lock notices before the JSON, so start parsing at the first "{").

Files to write:
- README.md: the record.
- One .md per prompt file (same base name, .md), the prompt text as is. For the three review prompts (review-170-prompt.txt, review-171-prompt.txt, review-351-prompt.txt) keep the review instructions and issue text but replace the diff with a one-line note saying the diff of PR #N at that point was included.
- One .md per turn output with the "text" field as is, named after the output file (for example r-156-1.md, review-170.md).
- summary.json copied as is.

README format: follow docs/runs/2026-11-01-codex-wrapper-prompt-stdin-154/README.md exactly in structure (title, one intro paragraph, Item/Value table, Turns table with links to the prompt and report files, Verification, Scorecard, Observations with Class and Response). Title: "# Three agent patterns over the agent call (run 6)". Differences for this run:
- The server was the #140 spike: the agent operation over codex_wrapper 0.9.0 and claude_wrapper 0.19.0, with no GenAgent or Ensemble on the turn path. Say so in the intro and the Item table.
- Three issues ran in parallel, one per pattern: single-use subagent (codex_wrapper #156, PRs #170 and #174), counterpart session (codex_wrapper #150, PRs #171 and #173), recursive session (claude_wrapper #315, PR #351). Group the Turns table by pattern.
- Scorecard: keep the Run 1 to Run 5 columns from the run 5 record and add three columns, Run 6 single-use, Run 6 counterpart, Run 6 recursive. Fill them from the operator notes. Step 5 is now "Session" (the agent call starts it). Step 8 and 9 should say who reviewed (independent Claude reviewer, the counterpart, or the implementer's self-started reviewer).
- Observations: include every finding in the operator notes (merge race, cwd removed under a session, opaque exit 2, Mix build lock under parallel calls, MIX_QUIET leak, stopped sessions leave no record, Claude inherit versus the creator's mode, reviewers finding disjoint defects, the operator's own wrong instruction on the breaking marker, the destructive-git block). Class is Mechanical or Behavioural.
- Costs: Claude reports a cost per turn; Codex reports none. Give the Claude total and say Codex is not included.

Writing rules: factual, short sentences, no em dashes, no marketing tone, no provider session ids. Finish with a short report listing the files written.

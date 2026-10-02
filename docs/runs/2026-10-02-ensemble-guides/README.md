# Ensemble workflow and Strategy documentation runs

On 2026-10-02, two independent Ensemble issues were claimed with
`status/in-progress` and run through named `gen_agent_server` instances in
clean core clones at `80c44d7`. The first lane corrected workflow guides
(#228); the second documented Strategy callbacks (#205). The exact
[control script](issue_handoff_used.exs), issue text, prompts/constraints,
configs, stage text and metadata, captured diffs, and review rounds are in
the numbered folders. Each managed instance was stopped after its stage
sequence. Package checks, Git, PRs, CI, and labels were caller-owned.

## #228 workflow guides

The [issue](228/issue.md) used Codex `gpt-6-luna` for triage, Claude
`claude-sonnet-5-5` for implementation (requested `sonnet`), and Codex
`gpt-6-astra` for review (CLI default). The first review found two incorrect
new claims: anonymous functions are valid in `config.exs`, and the current
Server catches strategy callback exceptions before stopping the session. It
also requested executable coverage. The caller archived the first
implementation text and metadata before the server's `revise` round; the
script archived the first review text automatically. The revised guide
passed review. The caller then removed six tests that only searched prose
fragments and kept three executable checks: Debate config module resolution,
Consensus config and parser execution, and Supervisor status shapes. A final
`review_only` pass approved that scope. The host ran 3 focused and 172 full
Ensemble tests, format, warnings-as-errors compile, strict Credo, docs
warnings-as-errors, and Dialyzer. [Core PR #357](https://github.com/genagent/gen_agent/pull/357)
contains the change.

## #205 Strategy contracts

The [issue](205/issue.md) used Codex `gpt-6-luna` for triage and
implementation, then Claude `claude-sonnet-5-5` for review. The implementation
added callback docs and focused tests for init rejection and status override.
The first review approved source semantics but the host test exposed missing
required callback stubs in a test-only strategy, which the caller added. The
second review asserted that init failure would kill the test process without
`trap_exit`; the focused host test had already passed without it. The caller
recorded that evidence, added the reviewer's useful callback-batch and
active-token clarifications, and requested a third read-only review. It
approved, explicitly accepting the host test as the authority on the false
trap-exit concern. The host ran 171 full Ensemble tests, format,
warnings-as-errors compile, strict Credo, docs warnings-as-errors, and
Dialyzer. [Core PR #356](https://github.com/genagent/gen_agent/pull/356)
contains the change.

Both lanes illustrate why reviewer findings, source checks, and executable
results need separate fields in a control API. A reviewer caught real
documentation mistakes; another generated a plausible but false runtime
blocker. The `revise` and `review_only` paths overwrite prior stage metadata
unless the caller archives it. This run preserved all review texts, but the
first #228 review metadata was overwritten by the script; the remaining
per-stage metadata and actual model observations are retained. A future
control API should append stage attempts atomically rather than reuse the
same filenames.

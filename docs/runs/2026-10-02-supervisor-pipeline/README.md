# Supervisor fan-out and Pipeline stage results

Two independent Ensemble strategy issues were claimed with
`status/in-progress` and run through named `gen_agent_server` instances in
clean core clones at `58ff446`. The exact [control script](issue_handoff_used.exs),
issue text, caller constraints, stage configs, stage text and metadata,
captured diffs, and review rounds are retained in the numbered folders.
Each managed instance was stopped after its stages. The caller owned package
checks, Git, PRs, CI and labels. The runner archived the first #214 review
text on `revise`, but overwrote its JSON metadata; the caller saved the first
implementation metadata. Post-review IEx-prefix and alias-order fixes are in
the linked PRs, after the archived combined diff.

## #214 Supervisor fan-out

[Issue #214](https://github.com/genagent/gen_agent/issues/214) used Codex
`gpt-6-luna` for triage, Claude `claude-sonnet-5-5` for implementation
(requested `sonnet`), and Codex `gpt-6-astra` for review (CLI default). The
first review found that a new default limit of 10 broke three existing
12-worker tests and that a new queued-run test could pass without actually
queueing. The caller archived the first implementation metadata before a
`revise` round. The revised tests set an explicit limit of 12 where needed
and use a deterministic strategy-level queue test. The second review
approved. The host ran 16 focused and 180 full Ensemble tests, format,
warnings-as-errors compile, strict Credo, docs warnings-as-errors, and
Dialyzer. [Core PR #358](https://github.com/genagent/gen_agent/pull/358)
passed CI and merged as `cd32dbc`; issue #214 closed and its claim was cleared.

## #220 Pipeline stage results

[Issue #220](https://github.com/genagent/gen_agent/issues/220) used Codex
`gpt-6-astra` for design and implementation (CLI default), then Claude
`claude-sonnet-5-5` for review (requested `sonnet`). The design pass found
that aggregate usage is already implemented; the remaining gaps were ordered
full stage results and total stage duration. It compared transient status,
a Pipeline-specific wrapper, and an additive `Response.metadata` field, then
chose the last to preserve existing return tuples and repeatable token reads.
The implementation stores only the active run's stage responses and adds no
historical cache; it clears that state on completion, error, cancellation
and dispatch rejection. The independent review approved, but one root test
run inside the review was unexplained 323/324 before three subsequent passes.
The caller's focused tests passed (11 core and 32 Ensemble); the full root
and Ensemble quality gates then passed, with 324 core and 184 Ensemble tests,
format, warnings-as-errors compile, strict Credo, docs warnings-as-errors,
and Dialyzer. An alias-order Credo finding was fixed outside the model.

The result crosses a publication boundary. Published `gen_agent` 0.6.2 has no
`Response.metadata`, while Ensemble's Hex dependency currently permits 0.6.
The caller split the additive core field into
[PR #359](https://github.com/genagent/gen_agent/pull/359), which passed CI and
merged as `02e6e01`. The Ensemble implementation is
[draft PR #361](https://github.com/genagent/gen_agent/pull/361), held until
core 0.7 is published and Ensemble can require it. The active streaming
draft and release PRs also edit `extensions/ensemble/mix.exs`, so that
constraint must be coordinated rather than changed concurrently. Issue
#220 remains open and claimed. A disposable checkout ran `GEN_AGENT_HEX=1
mix deps.get`, which resolved core 0.6.2, then `GEN_AGENT_HEX=1 mix test
test/gen_agent_ensemble/strategies/pipeline_test.exs`: 3/16 passed and 13
failed with `KeyError: key :metadata not found`. That concrete Hex-consumer
failure is the release gate; the run artifacts here show the combined diff
reviewed and tested in the monorepo.

These runs illustrate a useful two-lane pattern: a smaller bounded-resource
fix can merge while a larger result-contract change is staged behind its
published dependency. Reviewer approval and local monorepo tests do not prove
a Hex consumer can use the new field. The control layer should represent
that publication dependency explicitly rather than treating a green local
test as permission to release the dependent package.

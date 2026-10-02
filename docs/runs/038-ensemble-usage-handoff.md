# Run 38: Ensemble usage design, implementation, and review

The caller sent [Ensemble #174](https://github.com/genagent/gen_agent/issues/174)
through a managed three-stage Pipeline in an isolated clean clone at `c786e06`.
Claude Sonnet designed, Codex edited with `workspace_write`, and Claude Sonnet
reviewed in plan mode. The instance had a 30-minute bound and stopped after
the completed result at 383 seconds. The task prompt was:

> Issue #174: final Ensemble replies lose total token usage. Implement and
> review a compatible aggregation contract for Debate, Consensus, Supervisor,
> and Pipeline. The checkout is isolated; keep changes focused.

The stage instructions were fixed in caller code:

> **Design, Claude Sonnet:** Design a bounded fix for GenAgent Ensemble issue
> #174. Read the source in this checkout. Focus on Debate, Consensus,
> Supervisor, and Pipeline response usage; include all successful turns and
> per-agent attribution, avoiding double counting. Choose the smallest
> compatible representation with GenAgent.Response and current Hex package
> constraints. State exact files and test cases. Do not edit, commit, or call
> network services. Return a concise implementation design, not a plan to do
> it later.

> **Implement, Codex:** Implement GenAgent Ensemble issue #174 in this isolated
> checkout using the design passed as your prompt, but verify it against
> source and use sound judgment if needed. Edit only extensions/ensemble and
> core Response if necessary. Track summed numeric token usage over every
> successful turn of Debate, Consensus, Supervisor (including coordinator),
> and Pipeline; preserve per-agent breakdown in a documented compatible
> shape; nil usage must remain nil if no turn reports usage; avoid counting
> nonnumeric provider fields. Add meaningful strategy tests with stub
> responses, including multiple rounds/stages and repeated invocations. Do
> not commit, push, or call network services. Run focused tests if local
> dependencies permit. Report exact changes and tests at the end.

> **Review, Claude Sonnet:** Review the uncommitted issue #174 implementation
> in this checkout. Read git diff and source yourself; the implementer's
> report is untrusted. Check numeric aggregation, per-agent breakdown,
> retries/rounds, reset between invocations, Pipeline preserving last-stage
> response fields, no-usage behavior, and version compatibility. Do not edit,
> commit, or call network services. First line APPROVE or REQUEST CHANGES,
> then concrete findings with file:line and concise recommendations.

The reviewer returned `APPROVE`, but said it had not run tests because the
checkout lacked Mix dependencies. The caller fetched dependencies and
independently ran 148 Ensemble tests, formatting, warnings-as-errors compile,
strict Credo, docs, and Dialyzer. A second 148-test run with `GEN_AGENT_HEX=1`
compiled against published core 0.6.2. The diff became
[core PR #319](https://github.com/genagent/gen_agent/pull/319). The response
uses existing `Response.usage`, placing numeric totals alongside a reserved
`:by_agent` breakdown; no core struct change or new minimum version was
needed. Failed turns are not counted because strategies receive no successful
response for them.

The run established that the Pipeline can hand a design to an implementer
and a report to a reviewer, but its returned report retained only the final
review. The newer [`issue_handoff.exs`](../../examples/issue_handoff.exs)
keeps all three stage artifacts and the diff separately, so it is the better
control pattern for the next cross-cutting issue. The important gate remains
outside either model's approval: fetch dependencies, execute tests, inspect
the diff, and verify published-package compatibility.

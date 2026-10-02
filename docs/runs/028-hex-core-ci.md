# Run 28: Hex-core CI gate

This run used `examples/specs/implement_review_pipeline.json` against an
isolated clone of `gen_agent`. Codex had workspace-write access for the
implementation stage; Claude reviewed the uncommitted diff read-only. Both
used their CLI defaults. The server returned a completed invocation after
122 seconds. The review text, task, and timing were retained in the caller's
local run report; the server result exposed the final review, not a separate
implementation-stage artifact.

## Task given to the Pipeline

> For issue #248, implement a bounded Hex-core CI check. Edit only
> scripts/package-check.sh and, only if necessary, .github/workflows/ci.yml.
> The current packaging job builds Hex archives but does not compile or test
> siblings with GEN_AGENT_HEX=1. Add compile and test in Hex mode when the
> current root core version is already published on Hex; skip that additional
> gate with a clear message when it is not published, so core feature PRs can
> land before the core release. Refresh each sibling locked core dependency
> and assert that it resolves the root version before testing. Preserve the
> path-mode CI tests and archive metadata check. Do not alter package
> constraints or release scripts. Do not commit or push. Report changed files
> and tradeoffs.

The stage roles and their access limits are in the [Pipeline spec](../../examples/specs/implement_review_pipeline.json).
The target was `scripts/package-check.sh` in a clone based on core 0.6.1.
The finished change is [core PR #303](https://github.com/genagent/gen_agent/pull/303).

## What the run established

Claude returned `APPROVE` after reading the diff. It explicitly said it had
not run the script or accessed the network. The first independent execution
of `bash scripts/package-check.sh` failed: the implementation updated the
locked core dependency before fetching all sibling dependencies in the fresh
checkout. The caller added `mix deps.get` before the update and replaced a
direct lockfile evaluation with `Mix.Dep.Lock.read()` in a Mix context. The
full script then passed with published Hex core 0.6.1: Claude 58, Codex 58,
Anthropic 38, OpenAI 50, and Ensemble 129 tests; all six archives built.
Shell syntax and diff checks also passed. CI was pending when this record was
written.

The mechanical control rule is to run the real acceptance command after the
model stages, even when the reviewer approves. The behavioral lesson is
narrower: a read-only review can identify untested assumptions, but approval
without execution cannot certify the change. A future optional control API
could retain stage artifacts and attach an executable verification step with
its own status, rather than treating a review verdict as the gate.

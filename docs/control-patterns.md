# Control patterns seen in server dogfooding

Keep executable control code in `examples/` while its shape is still changing.
This inventory records the repeated steps, so an optional higher-level module
can be extracted from observed use rather than from a prompt template.

| Use | Executable example | Control steps worth keeping | Current boundary |
| --- | --- | --- | --- |
| Two-provider review | [`claude_codex_review.exs`](../examples/claude_codex_review.exs), [`claude_codex_debate.json`](../examples/specs/claude_codex_debate.json) | Give both stages the same project; obtain safe backend options through `Providers.backend_opts/2`; pass the draft as data to the verifier; require the verifier to check files; stop the temporary instance. | Pipeline owns stage handoff. The caller still chooses roles, models, and how to judge the finding. |
| Parallel independent review | [`codex_parallel_review.exs`](../examples/codex_parallel_review.exs), [`readme_audit_supervisor.json`](../examples/specs/readme_audit_supervisor.json) | Label tasks and worker replies; obtain safe backend options through `Providers.backend_opts/2`; admit independent work together; check for pending tokens; stop workers. | Supervisor owns fan-out and cleanup. The task list and synthesis rules remain caller choices. |
| Batch finding verification | [`verify_claims.exs`](../examples/verify_claims.exs), [`issue_verify_consensus.json`](../examples/specs/issue_verify_consensus.json) | Supply one claim per prompt; retain each verdict with evidence and elapsed time; report failures separately from unverified claims. | `GenAgentServer.Run.run/3` owns temporary instance setup, admission, result polling, timeout, and teardown. Verdict parsing is application code. |
| Mixed-provider issue batch | [Run 37](runs/037-three-issue-batch.md) | Claim non-overlapping issues first; start a bounded Codex Pool and Claude Solo as named `Run.run/3` instances, join both calls under a task supervisor, retain per-issue text and elapsed time, and stop both instances. Verify source claims and run package tests outside the responses. | The caller chose issue ownership, provider route, and follow-up action. The current `Run` report does not retain every Pipeline stage artifact; use the staged issue handoff for design, implementation, and review. |
| Second three-issue batch | [Run 40](runs/040-three-issue-triage.md) and its [literal control script](runs/040-control.exs) | Put two related, read-only checks in a Codex Pool and one risky core design in a Claude Solo; bound each named instance, join results, and clean up in `after`. Track issue claims separately from server worker names. | This temporary caller hardcodes paths and does not capture actual model IDs. A reusable control API should accept a task manifest and retain provider session metadata without taking over issue prioritization. |
| Design, implement, review | [`implement_review_pipeline.json`](../examples/specs/implement_review_pipeline.json), [run 38](runs/038-ensemble-usage-handoff.md) | Isolate the writable project, bound file edits, hand the change to a separate read-only reviewer, then verify tests and the diff outside the model response. | Pipeline moves stage text but returns only the final review; it does not commit, run CI, or accept a review. Use staged issue handoff when each stage artifact matters. |
| Staged issue handoff | [`issue_handoff.exs`](../examples/issue_handoff.exs) | Input: issue text, caller constraints, a fresh clean clone (not a Git worktree, whose metadata is outside the provider sandbox), and a provider and model per stage. Permissions: triage and review run in Claude plan mode or a Codex read-only sandbox; only the implement stage is given edit permission, scoped to the clone. Claude plan mode is not a filesystem sandbox (run 36), so treat the reviewer's checkout as disposable too. Run each stage as its own invocation on one managed Switchboard so every stage's text is kept; capture the diff with git outside the model; find the verdict line by search; read the model used from the CLI session file; persist each completed stage and a failed-stage record before stopping the instance. Completion: every stage returns a terminal result, or the script stops with the failing stage. | The script never commits, runs package checks, or accepts the review. Caller-specific: issue text, constraints, role and model choice, and acting on the verdict. Observed failures: ambiguous instructions (run 29), template acceptance text, provider preamble before the verdict, a requested model that the CLI ignored (run 30), and a reviewer that did not receive the implementer's constraints or saw new files only by name (run 31). Re-review after fixes with `review_only`, or run one bounded revise round with `revise`, which feeds the previous review to the implement stage and keeps each round's review as `review-round-N.md` (run 52). |
| Durable-for-process invocation | [`GenAgentServer.invoke/3`](../lib/gen_agent_server.ex), `GenAgentServer.result/2`, and the [`ops` CLI](../README.md#multiple-projects-in-one-server) | Keep the instance and invocation ID, poll until terminal, preserve a rejected admission separately, and allow repeatable result reads. | The result store survives callers, not a node restart. A caller timeout does not cancel the turn. |
| Answer presentation | [`GenAgentServer.CLI`](../lib/gen_agent_server/cli.ex) | Render `Response.final_message` for a human-facing final answer; keep `Response.text` and the original response for history and API consumers. | Message boundaries belong in the streaming response contract. A caller cannot reconstruct them from compact retained events or by splitting paragraphs. |

When adding an example, record the input and provider permissions, the pattern
used, the control steps outside the agent prompt, the observable completion
condition, and any failure or cleanup behavior. Link the corresponding run in
[`dogfooding.md`](dogfooding.md). Prefer `PatternSpec` and `Run` for temporary
batch work; use an instance-scoped `invoke`/`result` loop when later clients
need to read the same result. Keep source paths and tests as evidence for code
findings rather than treating a worker's verdict as proof.

The [#249/#259 issue runs](runs/2026-10-02-title-ensemble/README.md) add two
control details: a CLI backend may fail before any model event if the caller's
host sandbox blocks its session-state directory, so startup failure must be
recorded separately from a model verdict; and a staged issue can produce a
verified first slice while its parent issue remains open for explicit code
dependencies. These are host workflow states, not extra prompt instructions.

The [#259 cancellation run](runs/2026-10-02-ensemble-cancel/README.md) used a
bounded `revise` round after an approving model review missed strict Credo
failures and a child-call timeout risk. Preserve the original review and
pass the exact host failure into the next edit stage; approval, mechanical
verification, and PR acceptance remain distinct results.

The [#106/#206 runs](runs/2026-10-02-stream-docs/README.md) used a separate
read-only Solo design ahead of the staged handoff for a risky core API. A
reviewed revision fixed reproducible test failures, and a final `review_only`
pass checked a narrow caller-made integrity change. Reusing the existing
triage and implementation artifacts kept the extra review bounded. A Solo
`Run.run/3` result did not expose the provider session ID or actual model,
though the staged handoff did; an optional control API should preserve that
metadata consistently. Claude plan mode again substituted Sonnet for a
requested Haiku model, so the recorded actual model matters more than a route
declared in a prompt or config.

The [#259 streaming run](runs/2026-10-02-ensemble-stream/README.md) repeated
the read-only Solo design plus staged handoff pattern on a protocol boundary.
The caller checked the design against source before the write stage, which
corrected an early-event timing inference. The runner captured model/session
metadata and stopped its named instance; the caller owned package checks,
draft PR status, and the core Hex release gate. A future control API can expose
those as separate stage, validation, and release states without making a model
verdict authoritative.

The [#239 Pool guide run](runs/2026-10-02-pool-guide/README.md) exposed a
model-routing preflight gap: the local Codex CLI rejected `gpt-6.1-sol` for
this account even though the app advertised it. The runner failed before any
edit and stopped the instance, so the caller could preserve the clean clone
and retry with `gpt-6-astra`. A higher-level control API should report the
requested model, actual model, and stage failure distinctly; it should not
silently substitute a model. The successful review could not execute tests,
while host validation caught one strict Credo warning, so these gates also
need separate result fields.

The [#245 Workspace run](runs/2026-10-02-workspace-guide/README.md) timed out
mid-implementation with a useful diff but no saved triage or implementer text.
At that time, `issue_handoff.exs` wrote all stage artifacts only after review
completed. It now saves each successful stage before starting the next and
records a failed-stage outcome. The caller validated the diff and ran
`review_only`, whose summary explicitly marks the missing stages unavailable.
A control module should persist each
completed stage at its boundary and retain a terminal timeout or failed-stage
record; recovery should reuse the checkout without fabricating lost outputs.

The [#241/#237 runs](runs/2026-10-02-retry-switchboard/README.md) confirmed
the new stage-boundary files appeared while later stages were active. They
also exposed a second retention gap: `revise` archives the old review but
overwrites the implementer report and metadata. A high-level workflow result
should retain every stage attempt, including revisions and re-reviews, with
its own model, session, timing, and verdict instead of replacing the prior
attempt. Keep the host's tests and PR decision as separate gates.

The [#243 Checkpointer run](runs/2026-10-02-checkpointer-guide/README.md)
shows why an approving review and a passing host test should be distinct
stage results. Claude's implementation and Codex's review both checked the
protocol from source but could not run the new tests. The caller executed the
guide's compiled code, the full root suite, and quality gates before PR
action. The issue-specific review token and failure retry are application
behavior; the server's reusable control code supplied isolation, bounded
stages, captured artifacts, and cleanup.

The first candidates for an optional control module are repeated operations
that are currently duplicated outside `Run`: named-task attribution, terminal
result collection for a long-lived instance, and preserving stage artifacts for
review. Extract one only after at least two real callers need the same result
shape and failure policy. Provider roles, prompts, and verdict rules stay in
caller configuration; admission, ownership, timeout, and cleanup stay in code.

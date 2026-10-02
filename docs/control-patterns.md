# Control patterns seen in server dogfooding

Keep executable control code in `examples/` while its shape is still changing.
This inventory records the repeated steps, so an optional higher-level module
can be extracted from observed use rather than from a prompt template.

| Use | Executable example | Control steps worth keeping | Current boundary |
| --- | --- | --- | --- |
| Two-provider review | [`claude_codex_review.exs`](../examples/claude_codex_review.exs), [`claude_codex_debate.json`](../examples/specs/claude_codex_debate.json) | Give both stages the same project; obtain safe backend options through `Providers.backend_opts/2`; pass the draft as data to the verifier; require the verifier to check files; stop the temporary instance. | Pipeline owns stage handoff. The caller still chooses roles, models, and how to judge the finding. |
| Parallel independent review | [`codex_parallel_review.exs`](../examples/codex_parallel_review.exs), [`readme_audit_supervisor.json`](../examples/specs/readme_audit_supervisor.json) | Label tasks and worker replies; obtain safe backend options through `Providers.backend_opts/2`; admit independent work together; check for pending tokens; stop workers. | Supervisor owns fan-out and cleanup. The task list and synthesis rules remain caller choices. |
| Batch finding verification | [`verify_claims.exs`](../examples/verify_claims.exs), [`issue_verify_consensus.json`](../examples/specs/issue_verify_consensus.json) | Supply one claim per prompt; retain each verdict with evidence and elapsed time; report failures separately from unverified claims. | `GenAgentServer.Run.run/3` owns temporary instance setup, admission, result polling, timeout, and teardown. Verdict parsing is application code. |
| Design, implement, review | [`implement_review_pipeline.json`](../examples/specs/implement_review_pipeline.json) | Isolate the writable project, bound file edits, hand the change to a separate read-only reviewer, then verify tests and the diff outside the model response. | Pipeline moves stage text; it does not itself commit, run CI, or accept a review. |
| Durable-for-process invocation | [`GenAgentServer.invoke/3`](../lib/gen_agent_server.ex), `GenAgentServer.result/2`, and the [`ops` CLI](../README.md#multiple-projects-in-one-server) | Keep the instance and invocation ID, poll until terminal, preserve a rejected admission separately, and allow repeatable result reads. | The result store survives callers, not a node restart. A caller timeout does not cancel the turn. |

When adding an example, record the input and provider permissions, the pattern
used, the control steps outside the agent prompt, the observable completion
condition, and any failure or cleanup behavior. Link the corresponding run in
[`dogfooding.md`](dogfooding.md). Prefer `PatternSpec` and `Run` for temporary
batch work; use an instance-scoped `invoke`/`result` loop when later clients
need to read the same result. Keep source paths and tests as evidence for code
findings rather than treating a worker's verdict as proof.

The first candidates for an optional control module are repeated operations
that are currently duplicated outside `Run`: named-task attribution, terminal
result collection for a long-lived instance, and preserving stage artifacts for
review. Extract one only after at least two real callers need the same result
shape and failure policy. Provider roles, prompts, and verdict rules stay in
caller configuration; admission, ownership, timeout, and cleanup stay in code.

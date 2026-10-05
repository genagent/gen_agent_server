# Control patterns seen in server dogfooding

The [peer #104 fork](runs/2026-10-05-peer-104/README.md) separated a bounded
server fix from the parent session's adapter issue using a current-main clone.
No server worker or paid provider call ran. Its regression-first host checks
kept source failures, a later fixture teardown race, packaging and CI evidence
separate. Keep explicit issue ownership and checkout boundaries when a fork
is used for capacity; inherited conversation context alone is insufficient.

The [core #118 control run](runs/2026-10-02-core-118-control/README.md) used
server v0.2.0's nine-tool stdio MCP surface and quickstart resource, but each
ad hoc client script started its own VM. The next useful control step is one
supported path that keeps the real Fio PM session while technical inspection,
edits, tests, review, and release use a shared server instance; server
[#81](https://github.com/genagent/gen_agent_server/issues/81) remains
unimplemented and is the highest-value shared-instance usability gap.

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
| Dependent wrapper and adapter fix | [Codex options #123](runs/2026-10-02-codex-options-123/README.md) | Use a staged handoff for the wrapper, then validate the adapter in its own isolated checkout. Keep model review, host tests, wrapper source merge, published wrapper availability, adapter dependency resolution, and adapter CI as separate gates. | The server owns none of those gates after its temporary instance stops. A future control API should represent dependency publication and each validation outcome without equating them with a model's `APPROVE`. |
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

The [#238/#244 guide runs](runs/2026-10-02-debate-heartbeat-watcher/README.md)
used two named handoffs concurrently and then several bounded review-only
passes. Reviewers found bugs that passing guide tests initially missed: a
repeated Debate run could consume a previous completion message, and a ticker
could address a restarted agent between a PID check and a name-based notify.
The caller added focused regression tests and reran package gates. Each
`review_only` pass overwrote `review.md` and `review.json`, so the caller copied
them to round files before the next pass. `revise` similarly overwrote the
earlier implementation report. The optional control API should keep a
monotonic stage/round history and explicit host-validation results; choosing
which reviewer findings are blocking remains a caller decision.

The [#231/#236 runs](runs/2026-10-02-migration-supervisor/README.md) combined
an offline dependency-recipe fixture with a callback guide whose initial
passing tests missed two real queue-ordering failures. A source reviewer
found that queued user turns could be treated as synthesis and that a
rejected generated prompt could strand the coordinator. The caller fed
each exact failure into a bounded `revise` round and required a deterministic
test before continuing. Host verification used actual Mix dependency
resolution separately from the offline fixture, then full package gates,
CI, and merge. `revise` overwrote earlier implement metadata, and manually
archiving a review before `revise` duplicated the runner's archive; a control
API needs append-only attempts with stable round IDs. Stage verdicts and
host checks should remain separate completion conditions.

The [#230/#232 runs](runs/2026-10-02-hook-contributor/README.md) reused two
independent handoffs with different model costs: Codex Luna and Claude Haiku
were sufficient for a contributor guide, while hook execution context used
Claude Sonnet and Codex Astra. Source reviews caught omitted agent-process
checkpoint work and inaccurate Release Please wording. Host checks caught a
README link that ExDoc could not package and ran behavioral hook tests
outside the model session. A future control module should retain each review
and model choice with its exact stage attempt, not overwrite prior metadata;
task-specific claims still need host and reviewer checks.

The first candidates for an optional control module are repeated operations
that are currently duplicated outside `Run`: named-task attribution, terminal
result collection for a long-lived instance, and preserving stage artifacts for
review. Extract one only after at least two real callers need the same result
shape and failure policy. Provider roles, prompts, and verdict rules stay in
caller configuration; admission, ownership, timeout, and cleanup stay in code.

The [#110/#256 runs](runs/2026-10-02-core-tests-list/README.md) exercised a
two-lane issue pool on independent core files. One lane used Claude Sonnet
for implementation and Codex Astra for review; the other used Codex Astra
for implementation and Claude Sonnet for review. A read-only triage stage
removed a stale Checkpointer test finding before edits. The caller fetched
missing dependencies after the model review and ran root package gates and
Dialyzer independently. This supports a reusable claim/checkout/handoff/
validate/PR pattern, while package-specific acceptance commands and the
choice to skip already-resolved findings remain caller decisions.

The [#205/#228 Ensemble documentation runs](runs/2026-10-02-ensemble-guides/README.md)
show two distinct reviewer outcomes: source review caught incorrect claims
about `Config.Reader` and callback exception handling, but a later review
incorrectly predicted a test would exit without `trap_exit`. The host test
passed directly and the final review accepted that evidence. The caller
removed Markdown substring assertions in favor of executable config and
status checks. A control API should preserve each review finding, its
verification result, and stage attempt metadata separately; an approval or
request-changes line alone cannot represent this history.

The [#214/#220 strategy runs](runs/2026-10-02-supervisor-pipeline/README.md)
separated a bounded-resource fix from an additive result-contract change.
The first reviewer caught that a safe default could break existing 12-worker
coverage and that a queue test did not guarantee a queued request. The second
lane passed monorepo tests but crosses a Hex publication boundary: core must
publish `Response.metadata` before Ensemble may require and use it. An
optional control API should track dependent release gates as well as tests,
reviews and PR state; it must not equate a locally green branch with a
publishable package.

The [#196 wrapper and adapter runs](runs/2026-10-02-forcola-overlap/README.md) add a
useful cross-package gate: resolve disposable consumer projects with the
actual Hex versions and exercise the optional runtime path. The adapter
follow-up used a small Claude Haiku implementation and Codex Luna review;
the caller separately refreshed its lock and tested both published backends.
A source-level
version-string assertion would repeat the implementation without proving
that two wrappers can coexist. The first review asked for that evidence;
the caller updated the lockfile and ran the consumers before a second review.
The reusable control layer could retain external validation results and all
review rounds alongside stage artifacts, without deciding that every reviewer
request implies a source test.

The [core option validation run](runs/2026-10-02-core-options-99/README.md)
shows a smaller revision loop: triage identified the existing startup contract,
but the implementation still asserted a different error shape and used a sleep
in a cache-eviction test. Review requested changes, and the host corrected and
tested them. Store the review findings, revision, and host checks independently;
do not treat a completed implementation stage as verified work.

The [Codex usage run](runs/2026-10-02-codex-usage-124/README.md) first used
a read-only live provider probe to resolve whether resume counters are
cumulative. The staged worker then changed translation, while review and host
tests identified two distinct stale assertions. A control API should retain
probe evidence, raw-provider versus normalized expectations, review findings,
and host validation separately so a passed model stage cannot stand in for a
measured provider contract or a passing suite.

The [work-machine MCP probe](runs/2026-10-02-work-machine-mcp/README.md)
separated server capability from client permission policy. Codex discovered
the tool but denied its first call in a non-interactive run until the caller
explicitly approved the bounded Echo tools; Claude used an isolated config
and tool allowlist. A future control layer should record both the server's
allowlist and each host's tool policy. It cannot treat separate stdio MCP
connections as one shared instance: each starts a VM with its own invocation
IDs and result store.

The [Claude option validation run](runs/2026-10-02-claude-options-117/README.md)
used a revision and a final review-only pass on the same isolated clone.
The first host test disproved the initial implementation's compatibility;
two review rounds found different supported wrapper values missing from the
validator. Keep an append-only record of each review and its host test
outcome. A model's approval and a green set of newly written tests cannot
replace tests of existing supported inputs or the full package checks.

The [MCP lifecycle run](runs/2026-10-02-mcp-lifecycle/README.md) exercised
create, describe, invoke/ask, result, and stop through a packaged stdio client.
The same connection retained routes and results; another connection would own
a different VM. A control API should retain this connection scope as explicit
state rather than pretending a named instance is globally discoverable. The
run also compared requested models with provider session files: Codex honored
its choice, while Claude plan mode substituted Sonnet for a requested Haiku.
The caller changed the dynamic default to a limited-tool mode, then verified
Haiku through the full MCP path. This is a recurring pattern: expose the
configured model, but record the observed model separately when possible.

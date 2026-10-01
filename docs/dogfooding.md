# Dogfooding GenAgent Server

Run real, bounded work through the server before expanding its surface. Start
read-only, verify every finding outside the agent response, and raise the
coordination complexity one pattern at a time. A completed model response is
evidence about the task, not proof that external work or resources settled.

## Classifying observations

| Class | Examples | First response |
| --- | --- | --- |
| Mechanical | routing, quoting, admission, timeout, lost results, crashes, cleanup, configuration | Reproduce without a model where possible; fix the contract in code and add a focused regression test. |
| Behavioral | unsupported claim, weak decomposition, ignored instruction, poor prioritization | Preserve the task and evidence, refine the instruction or skill, then compare another run. |
| Mixed | missing instructions, unwanted tools, malformed handoff, tool failure hidden as model failure | Inspect the exact configuration and request/response boundary before assigning cause. |

Skills and examples can teach a workflow. Objective limits belong in code:
backend permissions, allowed operations, budgets, schemas, admission bounds,
stage gates, and result provenance. Do not rely on prompt text to enforce a
permission or to establish that a subprocess stopped.

## Runs

| Run | Real task and pattern | Observation | Class and action |
| --- | --- | --- | --- |
| Bootstrap | Codex reviewed the initial server through its Switchboard. | The CLI timeout was shorter than GenAgent's turn watchdog, so a caller could lose a late result. | Mechanical; fixed in [PR #1](https://github.com/genagent/gen_agent_server/pull/1) by waiting for the terminal turn outcome by default. |
| 1 | Echo and Codex shared a persistent Switchboard. Codex checked the README against the actual Mix and release paths. | Echo routed correctly; Codex found no reproducible documentation mismatch. A prompt containing an apostrophe broke the hand-written shell/Elixir RPC expression before reaching Codex. | Mechanical; add `mix gen_agent_server.remote`, which passes argument data through `System.cmd` and tests quotes and interpolation-looking text. |
| 2 | Codex reviewed the new remote command through that same persistent Switchboard. | It found that a regular but non-executable release file caused an uncaught `:eacces`. The issue was reproduced. | Mechanical; normalize process-start failure to a clear Mix error and add a regression test. |
| 3 | Echo submitted an invocation to a running OTP release. Two separate remote CLI calls read the same completed ID. | The result stayed available after the submitting RPC returned, with no consuming read. | Mechanical contract check for instance-scoped IDs and repeatable reads; tested in the instance-invocations change. |
| 4 | Claude and Codex independently reviewed the new invocation contract from a persistent Switchboard. | Claude still returned a usage-limit error. Codex identified that ID creation follows synchronous admission and that a completed turn could occupy capacity until the next inbox poll. | Mechanical; clarified the admission contract and collect completions before checking capacity. The Claude/Codex comparison remains incomplete until Claude can complete a turn. |
| 5 | An OTP release loaded a named `review` project profile. Separate remote commands listed instances, invoked Echo on `review`, and read `inv-4`. | The named instance remained addressable across commands and retained the completed result. | Mechanical contract check for profile startup and remote instance routing; Echo result matched the request. |
| 6 | Codex reviewed the named-profile README through the new `server-review` profile in a running release. | It found that the second terminal's example did not set `RELEASE_NODE`, so the remote commands might address the wrong node. | Documentation gap; added the explicit `export` before merging the profile PR. |
| 7 | Quantum `run_job/1` submitted a delayed Echo turn through the server's invocation API. | The job exposed an ID while active, a second run was rejected for overlap, and the completed Echo result was retrievable by that ID. | Mechanical integration check for opt-in scheduling; no Oban process or database was involved. |
| 8 | A built OTP release loaded an `echo-check` job and a named `review` profile. Separate remote commands listed the job, queued one run, found `inv-4`, and read its Echo result from `review`. | The scheduler and profile routing worked across commands in a live release. | Mechanical release smoke test; the cron timer itself was not awaited. |
| 9 | Codex used an explicit workspace-write profile in a disposable Git repository to append one line to `notes.txt`. | The result was retained and the file changed exactly as requested; `git status` showed no other changes. The displayed response concatenated Codex's progress text and final answer without a separator. | Write-path mechanics passed. The response presentation needs a separate look before treating it as an agent-behavior problem. |
| 10 | Echo ran a two-stage Pipeline and a two-worker Supervisor fan-out from the same OTP application. | Pipeline passed its first response into stage two. Supervisor returned both worker outputs and cleaned up the workers. | Initial deterministic pattern check used Ensemble directly; run 11 adds server-managed invocation IDs. |
| 11 | The Pipeline and Supervisor examples were moved under server-managed instances. | Each pattern now admits through one external route and exposes a repeatable server invocation ID; internal stage or worker names remain separate. | Mechanical integration check for strategy-neutral routing and result retention. |
| 12 | A built OTP release created a two-stage Pipeline through `rpc`; separate remote commands invoked its `pipeline` route and retrieved `inv-4`. | The returned text was `echo: echo: remote pattern` and the result survived the submitting RPC. | Mechanical release check for dynamic pattern instances and remote result reads; startup configuration remains application-owned. |
| 13 | Two read-only Codex stages reviewed scheduled-job handling through a managed Pipeline. | They identified that a present, non-list `jobs` field was silently treated as an empty schedule; source inspection confirmed the branch. The final response also combined messages without boundaries as in run 9. | Mechanical configuration bug; reject malformed `jobs` and test the distinction between absent and wrong-type fields. Message boundaries were fixed in [gen_agent #74](https://github.com/genagent/gen_agent/pull/74). |
| 14 | A read-only Codex turn reviewed result retention in the server after upgrading to published core 0.3.1 and Codex adapter 0.2.3. | The answer correctly identified that the instance's `:one_for_all` supervisor with `max_restarts: 0` stops the result store on child failure. Progress and final agent messages appeared as separate paragraphs. | Release integration check; the answer matches `GenAgentServer.Instance.init/1`, and the response boundary regression from runs 9 and 13 is resolved. |
| 15 | Claude and Codex independently reviewed retained results through the same server entry point. | Both identified the instance supervision boundary and volatile results. Claude also cited `restart: :temporary` and the 100-result default while explicitly limiting its claim about eviction because it had not read `Invocations`. | Behavioral comparison: agreement on a source-verified claim; no server defect observed. Claude completed after the usage reset. |
| 16 | A managed Pipeline sent a read-only Codex draft about remote-command reliability to Claude for verification. | Claude verified that `Remote.run/2` calls blocking `System.cmd/3` without its own timeout and corrected part of the draft's description of README commands. Source inspection confirmed the timeout claim. The server returned only Claude's final response, so the exact draft was unavailable for a fuller comparison. | Pattern handoff succeeded. Intermediate response provenance remains an explicit limitation of the current Pipeline result contract; use source checks for final claims and decide later whether opt-in stage artifacts are needed. |
| 17 | The reusable Codex-to-Claude Pipeline example reviewed duplicate project-profile names. | Claude verified the draft against `Profiles.load!/1` and its regression test, and explicitly limited the conclusion to file-loaded profiles. A first invocation exposed that `mix run FILE -- ARGS` passes `--` to `System.argv/0` for script files, so the documented command was corrected to `mix run FILE ARGS` before the successful run. | Read-only two-provider example works against a real project. The argument fix is mechanical; the provider's scoped conclusion is a useful behavioral check. |
| 18 | A managed Supervisor used an Echo coordinator to split independent read-only reviews of `remote.ex` and `invocations.ex` across two Codex workers. | Both labeled findings matched source: remote RPC calls use blocking `System.cmd/3` without a timeout, and completed results evict the oldest ID beyond the configured limit. Final status had only the coordinator, no in-flight work, and no pending tokens. | Fan-out, result attribution, and worker cleanup passed. The unbounded remote command wait is a separate mechanical reliability gap to address. |
| 19 | The reusable two-worker Codex example reviewed profile and job configuration separately. | One worker found that control characters in profile names could forge extra `instances` output lines; the other found invalid cron strings reached Quantum without job and file context. Source inspection reproduced both paths. | Mechanical; reject control characters and normalize cron during configuration loading, with focused regression tests. The parallel example completed and its workers stopped. |

The Codex CLI inherited local MCP configuration and logged connection warnings
for unavailable servers during these runs, though the turn completed. Track
that as environment/configuration noise rather than a model finding. Claude
could start but could not complete a live turn while account usage was
exhausted; no Claude behavior conclusion follows from that attempt.

## Next increments

1. Repeat one small read-only audit independently through Claude and Codex
   after Claude usage resets. Compare claims against files and tests; record
   disagreement or missing evidence as behavioral findings only after checking
   each provider's delivered instructions and tool access.
2. Try a read-only critique/revision task with Pipeline. Specify what each
   stage receives and how stage failure stops the run before asking a model.
3. Try Supervisor fan-out on independent, read-only files. Bound worker count
   and verify partial failure, late replies, and result attribution.
4. Only then try a write task in an isolated worktree, with a human-reviewed
   plan and ordinary test/PR validation. Keep server admission and result
   semantics explicit before adding multiple clients, MCP, or Oban.

For every run, note the exact pattern, provider versions, repository commit,
task, expected result, observed result, and whether the cause was mechanical,
behavioral, mixed, or still unknown. Avoid retaining secrets or full provider
transcripts in the repository.

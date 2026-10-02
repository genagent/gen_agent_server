I’ll keep this read-only and include an explicit comparison of the result-shape alternatives in the triage.


At checkout `58ff446583c74477f54c651cf9b92e6150bf3ad7`, this issue is **partially resolved**. No files were changed; findings below are from source inspection, not executed tests.

| Claim | Current finding |
|---|---|
| Pipeline forwards only text to the next stage | **Still true:** [pipeline.ex:90](/private/tmp/gen_agent_issue_220_20261002c/extensions/ensemble/lib/gen_agent_ensemble/strategies/pipeline.ex:90). |
| Earlier full responses are discarded | **Still true:** state retains stage names, phase, queue and usage only; [pipeline.ex:31](/private/tmp/gen_agent_issue_220_20261002c/extensions/ensemble/lib/gen_agent_ensemble/strategies/pipeline.ex:31). |
| Returned usage covers only the last stage | **Resolved:** each stage contributes usage, and the final response receives aggregate totals; [pipeline.ex:82](/private/tmp/gen_agent_issue_220_20261002c/extensions/ensemble/lib/gen_agent_ensemble/strategies/pipeline.ex:82). Existing tests cover successive runs, queued runs and recovery after errors; [usage_test.exs:69](/private/tmp/gen_agent_issue_220_20261002c/extensions/ensemble/test/gen_agent_ensemble/strategies/usage_test.exs:69). |
| Final response is returned unmodified | **Outdated:** usage is replaced, but other fields remain from the final stage; [pipeline.ex:93](/private/tmp/gen_agent_issue_220_20261002c/extensions/ensemble/lib/gen_agent_ensemble/strategies/pipeline.ex:93). |
| Duration covers only the final stage | **Still true:** Pipeline never aggregates duration. The response contract defines it as dispatch-to-terminal wall-clock time; [response.ex:20](/private/tmp/gen_agent_issue_220_20261002c/lib/gen_agent/response.ex:20). |
| Capturing intermediate results requires a custom strategy | **Overstated:** agent callbacks receive the full response through both `handle_response/3` and `post_turn/3`; [server.ex:1765](/private/tmp/gen_agent_issue_220_20261002c/lib/gen_agent/server.ex:1765). |

The current contract favors an additive response field. Strategies return `GenAgent.Response.t()` ([strategy.ex:92](/private/tmp/gen_agent_issue_220_20261002c/extensions/ensemble/lib/gen_agent_ensemble/strategy.ex:92)); Debate, Consensus and Supervisor construct that struct, while Solo, Pool and Switchboard pass selected responses through. There is currently no metadata/results field in [response.ex:26](/private/tmp/gen_agent_issue_220_20261002c/lib/gen_agent/response.ex:26).

The alternatives are:

- **Status or callbacks:** avoid changing `Response`, but do not provide a durable result associated with a completed token.
- **A new wrapper return type:** makes Pipeline diverge from the existing response contract and requires broader caller changes.
- **Defaulted metadata on `Response`: recommended.** Preserves existing fields and return tuples, requires no backend changes, and travels through existing completion storage unchanged.

The smallest concrete change would be:

1. **`lib/gen_agent/response.ex` and `test/gen_agent/response_test.exs`:** add and document `metadata: %{}` with a map type and a default-value test. Core should not depend on Ensemble types.

2. **`extensions/ensemble/lib/gen_agent_ensemble/strategies/pipeline.ex`:** accumulate raw `{stage_name, response}` pairs for the active run. On success, attach:
   ```elixir
   metadata.pipeline = %{
     stages: ordered_stage_responses,
     total_duration_ms: summed_stage_durations
   }
   ```
   Include every stage, including the unmodified final response. Preserve existing metadata, aggregate usage exactly as today, and leave top-level `duration_ms` unchanged. Explicitly define the new duration as the **sum of stage durations**, excluding queue wait and orchestration overhead.

   Clear the accumulator on completion, error, active cancellation and dispatch rejection; initialize it for both fresh and queued runs. Cancelling a queued token must preserve the active run’s accumulator.

3. **`extensions/ensemble/test/gen_agent_ensemble/strategies/pipeline_test.exs`:** add deterministic strategy tests with distinct full responses and known durations. Assert ordering, exact response preservation, aggregate usage/duration, single-stage behavior, and isolation after success/error/cancellation/rejection. Add integration tests for queued runs and repeated token reads, including late completions after cancellation.

4. **`extensions/ensemble/lib/gen_agent_ensemble/strategy.ex` and `extensions/ensemble/guides/workflows/pipeline.md`:** document the metadata shape, duration semantics, lifecycle and callback alternative; remove the obsolete “custom strategy required” guidance.

Existing token behavior supports this without editing the protected Ensemble server/main modules: `await` is repeatable ([server.ex:253](/private/tmp/gen_agent_issue_220_20261002c/extensions/ensemble/lib/gen_agent_ensemble/server.ex:253)), while `poll` and `inbox` consume results ([server.ex:299](/private/tmp/gen_agent_issue_220_20261002c/extensions/ensemble/lib/gen_agent_ensemble/server.ex:299)). Test repeated `await`, then consumption, preserving existing error tuples.

Retention would be limited to one active run’s configured stages plus existing completed-token storage—no additional historical cache. **The existing completed-token map itself has no automatic bound** ([server.ex:820](/private/tmp/gen_agent_issue_220_20261002c/extensions/ensemble/lib/gen_agent_ensemble/server.ex:820)). A strict global memory bound would require separate work in the protected server; that should stop for scope discussion rather than be folded into this change.
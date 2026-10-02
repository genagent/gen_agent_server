I’ll verify the response contract and Pipeline lifecycle, compare the result shapes, then implement and test the additive approach without editing the Ensemble server or main module.


The checkout confirms that Pipeline already aggregates usage and that completed tokens store the response unchanged. Status and callbacks cannot provide a repeatable completed-token result; a wrapper would change the shared response contract. I’ll add defaulted `Response.metadata` with ordered full stage responses and summed stage durations, preserving the final stage’s top-level duration.

The strategy will retain only the active run’s stages and clear them on completion or abort. Completed results will use existing token storage, which has no automatic global bound; this change adds no history cache.


The code and regression tests are in place, covering full response preservation, duration totals, token reads, queueing, cancellation, and failed-run cleanup. Mix cannot acquire its local TCP lock in this sandbox. I’ll try running the tests directly with Elixir and locally cached dependencies, without network access.


- [response.ex](/private/tmp/gen_agent_issue_220_20261002c/lib/gen_agent/response.ex): Added defaulted `metadata` map.
- [pipeline.ex](/private/tmp/gen_agent_issue_220_20261002c/extensions/ensemble/lib/gen_agent_ensemble/strategies/pipeline.ex): Retained ordered full stage responses and total duration, with lifecycle cleanup.
- [strategy.ex](/private/tmp/gen_agent_issue_220_20261002c/extensions/ensemble/lib/gen_agent_ensemble/strategy.ex): Documented the additive result contract.
- [pipeline.md](/private/tmp/gen_agent_issue_220_20261002c/extensions/ensemble/guides/workflows/pipeline.md): Documented inspection, duration, retention, and callback alternatives.
- [response_test.exs](/private/tmp/gen_agent_issue_220_20261002c/test/gen_agent/response_test.exs): Tested metadata defaults.
- [pipeline_test.exs](/private/tmp/gen_agent_issue_220_20261002c/extensions/ensemble/test/gen_agent_ensemble/strategies/pipeline_test.exs): Tested preservation, totals, token reads, and run isolation.
- [usage_test.exs](/private/tmp/gen_agent_issue_220_20261002c/extensions/ensemble/test/gen_agent_ensemble/strategies/usage_test.exs): Updated preservation assertions for metadata.

Validation: 195 tests passed using direct Elixir execution; Mix’s TCP lock was sandbox-blocked. `git diff --check` passed.
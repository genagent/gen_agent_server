# Run 37: three independent issue triages

The caller checked that core #305, release CI #251, and Ensemble #174 had no
active owner, claimed each with `status/in-progress`, and made a clean clone of
`gen_agent` at `c786e06`. The caller used two named `Run.run/3` instances
concurrently: a two-worker Codex Pool for #305 and #251, and a Claude Sonnet
Solo for #174. Each had an explicit read-only mode. The calls completed in
61 and 32 seconds respectively; the caller retained the exact task, outcome,
elapsed time, and worker text in a local JSON report, then stopped both
instances. The run script used `Task.Supervisor.async_nolink/2` and
`Task.yield_many/2` to bound the parallel calls.

The Codex Pool role was:

> Verify one issue against the current repository. Read files yourself; do not
> edit, commit, or call a live provider. Return VERDICT: CONFIRMED, REFUTED, or
> CHANGED on the first line. Then cite exact source locations, recommend the
> smallest fix and focused regression test, and identify any competing
> in-progress change. Keep it under 450 words.

The Claude Solo role was:

> Verify one Ensemble issue against the current repository. Read files
> yourself; do not edit or commit. Return VERDICT: CONFIRMED, REFUTED, or
> CHANGED on the first line. Cite exact source locations and propose a bounded
> usage-aggregation contract, including unknown keys, retries/multiple turns,
> per-agent breakdown, and focused tests. State ambiguities rather than
> inventing behavior. Keep it under 600 words.

The Pool received these two tasks, in order:

> Core issue #305: Task.Supervisor.async/2 in GenAgent.Server.dispatch exits
> with :noproc when a caller-owned task supervisor has stopped. The generic
> callback catch stops the agent and loses queued requests. Verify the current
> path and propose a typed error path and regression test. Inspect
> lib/gen_agent/server.ex and relevant tests. This is read-only triage.

> CI issue #251: release.yml grants write permissions at workflow scope, uses
> mutable action tags, and passes HEX_API_KEY to publish-package.sh for deps,
> compilation, tests, docs, and publishing. Verify current workflow and
> script. Propose least-privilege job permissions, action pinning approach,
> and a way to expose the key only to the publish command, with a check that
> would catch regression. This is read-only triage.

The Solo received:

> Ensemble issue #174: multi-agent Debate, Consensus, and Supervisor
> synthesize a Response with nil usage; Pipeline reports only its last stage.
> Verify the current implementation in extensions/ensemble and design a
> minimal compatible usage aggregation contract. Consider token-level
> completion and per-agent provenance. This is read-only triage.

The Codex
workers confirmed the unguarded task-supervisor dispatch and release workflow
exposure; Claude confirmed the missing aggregate usage and the Pipeline's
last-stage-only usage. The caller checked each finding against source before
editing. Core [PR #314](https://github.com/genagent/gen_agent/pull/314) and
CI [PR #315](https://github.com/genagent/gen_agent/pull/315) followed with
full local core suites and targeted regression tests. #174 was sent to a
separate design, implementation, and review pass because its response shape
crosses strategy and package boundaries.

The first Codex worker began with progress narration despite the first-line
verdict instruction; another said PR discovery was unavailable from its
environment. Those are behavioral and environment observations, not evidence
against the source findings. The useful control pattern is to claim and label
independent issues before fan-out, keep source verification and testing outside
the model result, and route a cross-cutting issue into a sequential handoff.
`Run.run/3` retained only the final response for a Pipeline; the staged
handoff example now retains separate stage artifacts, and
[server #40](https://github.com/genagent/gen_agent_server/issues/40) tracks a
reusable optional control API for this workflow.

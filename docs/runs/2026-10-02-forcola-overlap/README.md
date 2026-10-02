# Forcola 0.4 compatibility across the CLI wrappers

[Core issue #196](https://github.com/genagent/gen_agent/issues/196) was claimed
with `status/in-progress`. The Codex wrapper had no open overlapping PR or
issue. The caller cloned its `main` at `d521ee1` into
`/tmp/codex_wrapper_forcola_196` and ran the
[staged handoff](../2026-10-02-supervisor-pipeline/issue_handoff_used.exs)
through one named GenAgent Server instance. The control code's exact triage,
implementation, and review prompt templates are in that file. The
[issue text](codex_wrapper_forcola_196_issue.md),
[initial constraints](initial-notes.md), [initial config](initial-config.json),
stage texts and metadata, and captured final [diff](diff.patch) are here.
The first `mix run` could not start because the isolated server checkout had
no dependencies. `mix deps.get` fetched them; the next run completed. The
server stopped its instance after each invocation.

Codex `gpt-6-luna` triaged and edited the wrapper. Claude
`claude-sonnet-5-5` reviewed it. The first review, in
[review-round-1.md](review-round-1.md), requested real resolution and runtime
evidence for Forcola 0.4.0. Its session was
`5b756b8b-3ff3-4567-9cf1-65fa55774b2e`, with 24,175 ms elapsed;
the script overwrote this round's JSON on re-review. The caller then updated
`mix.lock` to 0.4.0 and ran the package checks. The
[0.4 consumer](probes/dual-04-mix.exs) resolved the path Codex wrapper,
published Claude wrapper 0.14.5, and Forcola 0.4.0 together; the
[0.3.5 consumer](probes/codex-035-mix.exs) resolved the older line.
Both compiled the Codex wrapper and returned `{:ok, {"ready\n", 0}}`
from its real Forcola runner. The 0.4 consumer also compiled Claude wrapper.
`mix test` in the wrapper passed 406 tests with four integration-tagged tests
excluded. Format, strict Credo, docs with warnings as errors, and
`git diff --check` passed. Two existing test-module type warnings appeared
under the newer compiler; neither was introduced by this dependency diff.

The caller added these host results to the [review-only constraints](codex_wrapper_forcola_196_notes.md),
archived the first review text, and ran the same control code with
[review_only config](codex_wrapper_forcola_196_config.json). The final
[review](review.md) approved. The reviewer checked Forcola 0.4's API and
the docs against the diff, while treating caller-run tests as a separate
gate. A test asserting the dependency string would only mirror the source;
the two disposable Mix consumers tested the actual resolver and runner.

[Wrapper PR #105](https://github.com/genagent/codex_wrapper_ex/pull/105)
passed CI and merged as `ad0b412`.
[Release PR #106](https://github.com/genagent/codex_wrapper_ex/pull/106)
merged; its publish job succeeded, and both the GitHub release and Hex list
Codex wrapper 0.5.4.

## Codex adapter floor

The caller then cloned `gen_agent` main at `02e6e01` into
`/tmp/gen_agent_forcola_196`, without touching another session's working
checkout. A second named server instance used Codex `gpt-6-luna` for triage,
Claude `claude-haiku-4-5-20251001` for implementation (requested `haiku`),
and Codex `gpt-6-luna` for review. The exact
[config](adapter/gen_agent_forcola_196_config.json),
[constraints](adapter/gen_agent_forcola_196_notes.md), stage outputs and
metadata, [review](adapter/review.md), and both the model-captured
[diff](adapter/diff.patch) and final [diff](adapter/final.diff.patch) are
retained. The review approved before the caller refreshed the lockfile.

The adapter now requires published Codex wrapper 0.5.4 and recommends
Forcola 0.4.0. Its 82 tests passed with three live-tagged tests excluded;
format, strict Credo, docs with warnings as errors, and diff check passed.
The [published-package consumer](adapter/probes/mix.exs) ran with
`GEN_AGENT_HEX=1` and resolved core 0.6.2, Claude adapter 0.2.2, Claude
wrapper 0.14.5, Codex wrapper 0.5.4, and Forcola 0.4.0. Both adapter modules
compiled and loaded, and the Codex Forcola runner returned
`{:ok, {"ready\n", 0}}`. The [lockfile](adapter/probes/mix.lock) records
the exact resolved versions.

[Core PR #362](https://github.com/genagent/gen_agent/pull/362) passed all CI
gates and merged as `378ff10`. Its generated
[release PR #363](https://github.com/genagent/gen_agent/pull/363) merged, and
the Hex publish job succeeded. Both Hex and GitHub list Codex adapter 0.4.3.
The final [fully published consumer](published-consumer/mix.exs) resolved
core 0.6.2, Claude adapter 0.2.2, Codex adapter 0.4.3, Claude wrapper
0.14.5, Codex wrapper 0.5.4, and Forcola 0.4.0, as recorded in its
[lockfile](published-consumer/mix.lock). Both adapters compiled and loaded;
the Codex Forcola runner again returned `{:ok, {"ready\n", 0}}`.
[Issue #196](https://github.com/genagent/gen_agent/issues/196) was closed
and its `status/in-progress` label cleared after this check.

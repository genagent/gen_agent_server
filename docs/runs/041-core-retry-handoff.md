# Run 41: caller-owned retry design, implementation, and review

The runnable server used [`examples/issue_handoff.exs`](../../examples/issue_handoff.exs)
against a clean gen_agent clone at `03fcc02`. The literal
[configuration](041-config.json), [issue prompt](041-issue.md), and
[design input](041-design-input.md) are retained here. The handoff script's
triage, implement, and review templates supplied the rest of each exact
prompt, including the same issue and constraints at every stage. Its control
code required a clean checkout, bounded each stage to 20 minutes, captured
the diff outside model text, and stopped the named Switchboard instance.

| Stage | Permission | Requested model | Actual model | Evidence |
| --- | --- | --- | --- | --- |
| Triage | Claude plan mode | `opus` | `claude-opus-5-5` | Confirmed the lost original result and designed ref, retry, halt, interrupt, and telemetry contracts. |
| Implement | Codex workspace-write | CLI default | `gpt-6-astra` | Changed core, docs, and deterministic tests in the isolated clone. |
| Review 1 | Claude plan mode | `sonnet` | `claude-sonnet-5-5` | Requested updates to the Retry guide and primitive example; these also exposed a stale Chaos Lab assertion. |
| Review 2 | Claude plan mode, `review_only` | `sonnet` | `claude-sonnet-5-5` | Requested a runtime-snapshot typespec, clearer README, and an explicit event-error follow-up test. |
| Review 3 | Codex read-only, `review_only` | CLI default | `gpt-6-astra` | Found stale `tell_with_completion/4` documentation. Its CHANGELOG request conflicts with release-please ownership, so the breaking `feat!` commit and migration guide carry the change. |

Independent checks after the final fixes passed: 218 core tests, all six
primitive scripts, the Chaos Lab, format, strict Credo, Dialyzer, and docs.
The example checks required `MIX_OS_CONCURRENCY_LOCK=0` in this sandbox and
Hex dependency fetching outside the model turn. A plan-mode reviewer claimed
it could not run `mix test`; another review reported 217/218 tests due a
read-only sandbox denial of `mktemp`. These are claims about the reviewer's
environment, not evidence of a project test failure. The caller ran the
project checks in its own checkout and obtained the passing results.

The tested change is [draft core PR #331](https://github.com/genagent/gen_agent/pull/331).
It is held for release sequencing: merging a breaking core change while
core 0.7.0 and dependent package compatibility are pending would change the
release candidate under test.

Reusable control steps: preserve every stage artifact; re-review the *current*
diff after correcting findings; run examples as well as unit tests when a
behavioral contract changes; keep release-generated changelogs out of manual
edits; and treat model reports about their own tool permissions as unverified
until the caller runs the required checks. Role text guides behavior, while
read-only and edit permissions are supplied in backend options.

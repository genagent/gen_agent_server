# CI title and Ensemble token runs, 2026-10-02

These are two independent, named tasks admitted through the runnable server. The
caller claimed gen_agent #249 and #259 with `status/in-progress` before starting
workers. Each worker used its own clean `gen_agent` clone; the server control
checkout was `c86546f`. The caller, not the agents, owned tests, PR actions,
and issue state. The exact stage runner at the time was saved as
[`issue_handoff_used.exs`](issue_handoff_used.exs): it starts a
managed Switchboard, grants only the implementation stage edit permission,
retains triage/implementation/review artifacts, captures the diff outside the
model, and stops the instance in `after`. Each stage had a finite timeout.
The installed provider CLIs were Codex 0.157.1 and Claude Code 2.1.284.

## #249: PR titles

Literal inputs: [issue](gen_agent_issue_249_prompt.md),
[instructions](gen_agent_issue_249_notes.md), and
[stage configuration](gen_agent_issue_249_config.json). The runner supplied
its checked-in stage prompt templates; the instance ID, base commit, model
choices, elapsed times, and usage are in [the retained summary](249-summary.json).

| Stage | Provider and actual model | Outcome |
| --- | --- | --- |
| Triage (read-only) | Codex, `gpt-6-astra` | Confirmed the missing check and the need to rerun on title edits. |
| Implement (workspace write) | Codex, `gpt-6-astra` | Added a PR-only workflow and a standard-library Python validator and tests. |
| Review (plan mode) | Claude, `claude-sonnet-5-5` | APPROVE; noted that accepting any alphabetic type follows the Conventional Commit syntax but does not guarantee a release-please version bump. |

The host ran `python3 scripts/test_pr_title.py` (3 test methods) and
`actionlint .github/workflows/pr-title.yml`; both passed. GitHub's new
`Conventional Commit title` check passed on
[PR #335](https://github.com/genagent/gen_agent/pull/335). Every core CI job
passed, and the caller merged it at `28702d6`, closing #249. The runner did
not commit, push, or merge. The caller did those separately after reviewing
the diff. This is a mechanical safeguard; #246 still owns required checks and
release gating.

The first invocation failed before triage returned: the host sandbox denied
Codex writes to `~/.codex/state_5.sqlite` and the CLI could not initialize its
in-process client, so the runner reported `:no_terminal_event`. The caller
restarted the same config with the already-authorized CLI filesystem access;
the recorded summary is from that successful retry. No failed-stage model
result was treated as a verdict.

## #259: Ensemble token design

The literal [design control script](gen_agent_issue_259_design.exs) used a
read-only Claude Opus Solo against a separate clean clone. It completed in
161,036 ms. Claude confirmed the issue on `26e2496`, but found that forwarding
stream events with token identity depends on open core #106. It recommended a
small completion/await slice, then strategy-aware cancellation, with stream
forwarding after #106. This dependency was checked against core's
`handle_stream_event/2` and request-ref API, not accepted on model authority.
The Solo `Run` result did not retain the CLI session ID or actual selected
model; `opus` is the requested model in the literal spec. This remains a
result-attribution gap for the planned workflow control API.

The first-slice inputs are the literal [issue
prompt](gen_agent_issue_259_slice_prompt.md),
[instructions](gen_agent_issue_259_slice_notes.md), and
[stage configuration](gen_agent_issue_259_slice_config.json). They explicitly
defer cancellation and stream forwarding, keeping #259 open. See the
implementation/review outcomes are in
[the retained summary](259-slice-summary.json). Codex `gpt-6-astra` handled
read-only triage and the isolated edit; Claude `claude-sonnet-5-5` approved a
read-only review. The host added a caller-default completion recipient after
review and independently ran 158 Ensemble tests, format, strict Credo,
Dialyzer, docs with warnings as errors, and `git diff --check`. It then opened
[PR #337](https://github.com/genagent/gen_agent/pull/337). Cancellation and
stream forwarding remain on #259; the PR is intentionally a first slice and
does not close it.

## Control observations

- One shared server control checkout can route separate issue checkouts through
  different providers while the caller preserves issue ownership and external
  validation. Distinct instances and output directories kept artifacts apart.
- Model roles and prompts guided scope. Read-only and edit modes, per-stage
  timeouts, and instance teardown were enforced by the runner/backend options.
- Claude plan mode wrote a plan under `~/.claude/plans` even though the prompt
  requested no edits. Plan mode is behavioral and not a filesystem sandbox;
  this did not alter the isolated project checkout.
- The stream-forwarding prerequisite is a code dependency, not a behavioral
  instruction that can be fixed with a better prompt.
- All three managed instances reached terminal results and were stopped in the
  runner's `after` block. The issue checkouts and small prompt/summary files
  were retained only for PR validation and this run record; no server-side
  worker remains active.

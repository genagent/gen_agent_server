# Workspace guide issue run

This run addressed [gen_agent #245](https://github.com/genagent/gen_agent/issues/245)
in an isolated clone at base commit `22de093`. The [issue](gen_agent_issue_245.md),
[caller constraints](gen_agent_issue_245_notes.md), [first configuration](gen_agent_issue_245_config.json),
and [literal control code](issue_handoff_used.exs) are retained. The first handoff
requested Claude Opus for read-only triage, Codex `gpt-6-astra` for implementation,
and Claude Sonnet for read-only review, with a 1,200,000 ms per-stage deadline.
It stopped during implementation with the exact error
`implement stage failed: :timeout`. The implementer had changed the guide and
created its test, but the script writes stage artifacts only after all three
stages finish, so it did not preserve the triage text, implementation report,
session IDs, or actual models. The local Codex process also reported a broken
stdout pipe after the caller timed out. This is a control-plane failure, not
evidence that the source change failed.

The caller retained that diff, fetched dependencies, then ran the executable
guide test (19 passed), the full core suite (251 passed), formatting, strict
Credo, docs with warnings as errors, and diff checks. The
[review-only configuration](review_config.json) then sent the current diff to
a read-only Claude Sonnet stage through the same server control script.
Its [summary](summary.json) records the actual `claude-sonnet-5-5` model, session,
77-second review, changed files, and `APPROVE` verdict. The [review](review.md)
explicitly says it did not run tests. It identified two stale descriptions of
`post_run/1`; the caller fixed those and repeated the docs and diff checks.
The recovered `triage.md` and `implement.md` are the script's explicit
`(not available)` markers, not reconstructed model outputs. The source fix is
[gen_agent PR #345](https://github.com/genagent/gen_agent/pull/345),
merged as `e9920af`. Its first CI attempt passed the Workspace tests but
failed an existing OTP 29 test cleanup race and a Claude example job that
received HTTP 500 fetching a Forcola binary. Both failed jobs passed on a
targeted retry; the package archive gate then passed.

Mechanically, a timeout can leave valid edits without a terminal implementation
response. Save each completed stage immediately, and make a later review-only
run possible without pretending earlier artifacts exist. Keep model review,
caller-run tests, and CI as separate evidence. The named server instance was
stopped by the script's `after` cleanup in both invocations.

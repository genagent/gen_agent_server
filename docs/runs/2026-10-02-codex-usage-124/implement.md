I changed the Codex adapter so `response.usage` is the increase since the previous completed turn, with all five counters kept. I did not run `mix format`, `mix test` or anything else, because the shell blocked every command that would run them. The host should run them, since nothing here has been compiled or tested.

All paths are under `integrations/codex/`.

- **`lib/gen_agent/backends/codex/event_translator.ex`**:
  - It keeps all five counters, including zeros and maps that contain only optional counters.
  - It takes a `:usage_baseline` option, which defaults to all zeros, and emits per-field deltas.
  - It omits a delta for any field that is missing from the baseline or has decreased, and omits `:usage` entirely when no delta remains.
  - It puts the raw completed total in the `:result` data as `usage_total`.
- **`lib/gen_agent/backends/codex.ex`**:
  - The session gets a `usage_total` field. It starts at zero for `start_session` and is empty (unknown) for `resume_session`.
  - The baseline is passed to the translator and replaced in `update_session/2` on each completed turn, even without a thread ID.
  - Checkpoints and failed or interrupted turns leave the baseline alone. A turn with no usage clears it rather than leaving a stale one.
  - The module docs describe these semantics.
- **`README.md`**: new "Usage" section and an updated `turn.completed` row. They cover the unknown baseline after an external resume, resets and missing fields, and the fact that a failed attempt's tokens land in the next successful delta.
- **`test/support/codex_transcripts.exs`**: the expected values now include all five fields and `usage_total`, and the stale issue #124 comment is gone.
- **`test/.../event_translator_test.exs`**:
  - Added tests for first turn with all five fields, resumed delta, unknown baseline, missing fields, optional-only counters, decreased counters, and malformed counters.
- **`test/.../codex_test.exs`**:
  - Added backend sequence tests for first and resumed turns, external resume, failed turn between completions, checkpoint, reset, and no-usage turn.
- **`test/.../codex_integration_test.exs`**:
  - The recorded resume pair now asserts the follow-up reports 14982 input tokens.
  - A new test uses the host's live totals and asserts 16294.

Core `Event` and `Response` are unchanged. The core `Event` and `Response` modules still have no wording about Codex's usage semantics, as I kept the change inside the adapter.

I also left a temporary helper script at `/private/tmp/gen_agent_fix_124_20261002/fix124.py`. It was never run and my `rm` of it was blocked, so please delete it.
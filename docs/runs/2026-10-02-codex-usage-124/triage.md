I’ll keep this review read-only and local, with findings tied to the current checkout’s file and line numbers.


At `b3173fe`, **both defects remain**. No files were edited; no tests or network commands were run.

Claims that still hold:

- **Two fields are dropped.** [`event_translator.ex:173`]( /private/tmp/gen_agent_fix_124_20261002/integrations/codex/lib/gen_agent/backends/codex/event_translator.ex:173) extracts only input, output, and cached-input tokens. It also suppresses usage entirely when input and output are absent, even if another counter is present.
- **Resumed totals reach responses unchanged.** [`codex.ex:131`](/private/tmp/gen_agent_fix_124_20261002/integrations/codex/lib/gen_agent/backends/codex.ex:131) translates without a usage baseline; the session stores no previous total (`:86`), and `update_session/2` only records the thread ID (`:149`). Subsequent calls use `ExecResume` (`:200`). [`response.ex:147`](/private/tmp/gen_agent_fix_124_20261002/lib/gen_agent/response.ex:147) copies the latest usage map unchanged.
- **External resumes have no baseline.** [`codex.ex:161`](/private/tmp/gen_agent_fix_124_20261002/integrations/codex/lib/gen_agent/backends/codex.ex:161) restores only the thread ID.
- **Usage semantics remain undocumented.** [`event.ex:16`](/private/tmp/gen_agent_fix_124_20261002/lib/gen_agent/event.ex:16), [`response.ex:19`](/private/tmp/gen_agent_fix_124_20261002/lib/gen_agent/response.ex:19), and the [Codex README:224](/private/tmp/gen_agent_fix_124_20261002/integrations/codex/README.md:224) do not distinguish cumulative totals from deltas.
- **Tests currently preserve the bugs.** [`codex_transcripts.exs:38`](/private/tmp/gen_agent_fix_124_20261002/integrations/codex/test/support/codex_transcripts.exs:38) expects cumulative totals and explicitly notes the dropped fields. The [recorded resume test:122](/private/tmp/gen_agent_fix_124_20261002/integrations/codex/test/gen_agent/backends/codex_integration_test.exs:122) checks identity and text, not usage deltas. [Live usage assertions:83](/private/tmp/gen_agent_fix_124_20261002/integrations/codex/test/gen_agent/backends/codex_live_test.exs:83) still only check positive first-turn counts.

Already resolved or superseded:

- **The evidence gap is closed:** the recorded [initial:4](/private/tmp/gen_agent_fix_124_20261002/integrations/codex/test/fixtures/codex/0.157.1/resume-initial.jsonl:4) and [resumed:4](/private/tmp/gen_agent_fix_124_20261002/integrations/codex/test/fixtures/codex/0.157.1/resume-followup.jsonl:4) completion lines contain all five fields and input totals `14956 → 29938`. Your independently verified live run supplies additional confirmation.
- **Thread identity survives failure/interruption**, through [`checkpoint_session/2`:158](/private/tmp/gen_agent_fix_124_20261002/integrations/codex/lib/gen_agent/backends/codex.ex:158). Usage accounting does not yet use this capability.
- Neither usage defect itself is resolved.

Smallest concrete change, confined to `integrations/codex/`:

1. **`lib/gen_agent/backends/codex/event_translator.ex`:** Preserve all five supplied counters, including zero values and maps containing only optional counters. Accept baseline context for delta calculation. Carry the raw completed total in a Codex-specific terminal-data key for session updates.
2. **`lib/gen_agent/backends/codex.ex`:** Store the previous completed total: known zero for fresh sessions, unknown for external resumes. Pass it to translation and replace it on successful completion—even without a newly emitted thread ID. Preserve it across checkpoints and failures.
   - Unknown baseline: omit usage, record the completed total, then report deltas on subsequent completions.
   - Missing fields: omit unavailable deltas; do not invent zeros or subtract stale counters across missing completed samples.
   - Decreasing counters: suppress affected deltas and rebaseline; never emit negative usage or silently treat a reset total as turn usage.
3. **`README.md` and adapter module docs:** Define usage as the increase since the previous completed total. Explicitly explain that intervening failed/interrupted attempts can contribute to the next delta; completion totals cannot isolate that consumption. Document unknown-baseline and reset behavior. Leave core contracts unchanged.
4. **Tests:** Extend `event_translator_test.exs`, `codex_test.exs`, and `codex_integration_test.exs` for all five fields, first/resumed turns, external resume, missing counters, resets, and success–failure/interruption–success sequences. Update `test/support/codex_transcripts.exs` and executable-conformance expectations to distinguish raw totals from adapter deltas. Assert recorded second-turn input usage **14982**, and the host-provided example **16294**. Preserve the raw fixtures.
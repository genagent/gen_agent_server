# fix(codex): report per-turn usage on resumed threads and keep reasoning and cache fields
https://github.com/genagent/gen_agent/issues/124

Found in a read-only review of `main` at `b8f8ab4`. Code links point at that commit; `main` has moved since (core 0.4.0).

## Problem

extract_usage (event_translator.ex:143-160) keeps input_tokens, output_tokens and cached_input_tokens and drops reasoning_output_tokens and cache_write_input_tokens, which Codex CLI 0.157.1 emits. Separately, the CLI fills turn.completed.usage from the thread's running total and seeds that total from the rollout on exec resume. Because the backend runs every turn after the first through ExecResume, response.usage on turn N is the cumulative thread usage, not the turn's. Local codex_exec 0.157.1 rollouts show the total carrying across resumed turns (input_tokens 19765, 50988, 84209, 123957 over four turns). The emitted turn.completed line itself was not captured from a live run; that step rests on upstream source at the matching tag. Neither the core Event/Response docs nor the Codex README states the semantics, and the other backends report per-request or per-run usage. Fix: pass through all five fields, then either store the previous total on the session and emit the delta, or document that Codex usage is thread-cumulative.

**Evidence.** event_translator.ex:143-160. Upstream codex-rs/exec/src/exec_events.rs:60-73 defines Usage with input_tokens, cached_input_tokens, cache_write_input_tokens, output_tokens, reasoning_output_tokens. event_processor_with_jsonl_output.rs:118-129 builds it from usage.total of the last ThreadTokenUsageUpdated notification; codex-rs/core/src/session/mod.rs:1631-1636 seeds token info from the rollout on resume. Translator run on a usage map with all five fields returned %{input_tokens: 5, output_tokens: 3, cached_input_tokens: 1}. The cumulative behaviour was read from upstream main and not measured against the installed CLI; the live test (codex_live_test.exs:83-85) only asserts the counts are positive on a first turn.

**Scenario.** A cost dashboard sums response.usage.input_tokens over a 10-turn Codex agent. If totals are cumulative, the sum grows quadratically compared with real consumption. Reasoning tokens are never visible.

Reproduction from the review (private checkout, stub backend or fake CLI, no provider called):

```text
Field dropping, in integrations/codex/test/v11_usage_test.exs:

  ev = %CodexWrapper.JsonLineEvent{event_type: "turn.completed", data: %{"usage" => %{"input_tokens" => 626_594, "cached_input_tokens" => 567_936, "cache_write_input_tokens" => 7, "output_tokens" => 2634, "reasoning_output_tokens" => 799}}}
  events = GenAgent.Backends.Codex.EventTranslator.translate([ev])
  GenAgent.Response.from_events(events, []).usage
  # => %{cached_input_tokens: 567936, input_tokens: 626594, output_tokens: 2634}

Run with: cd integrations/codex && mix deps.get && MIX_ENV=test mix test test/v11_usage_test.exs (1 passed, output as above).
```

## Proposed fix

- Pass through all usage fields. Verify cumulative versus per-turn semantics with a two-turn live run, then either subtract the previous total (stored on the session) or document the semantics in the README and in GenAgent.Event's usage contract.

## Acceptance

- A regression test reproduces each scenario above and passes after the change.

## Verification

- Confirmed by an independent code trace and reproduced by running code.


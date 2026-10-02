Found by the 2026-10-01 review at `b8f8ab4` and re-verified against `main` at `1a03608` by a read-only Codex worker in a `gen_agent_server` verification pool (genagent/gen_agent_server#25). One verifier per finding: treat file and line references as the starting point for the fix, and re-check them.

## Problem

### Debate guide gives the second agent one turn fewer than max_rounds and never delivers the first agent's final statement

When agent A reaches `max_rounds` it sends `{:debate, :done}` instead of its text and halts. B halts on that event without responding. B therefore produces `max_rounds - 1` turns, A's last statement is never shown to B, and with `max_rounds: 1` B never speaks. The guide text says both sides "reach a round cap and halt together".

**Verification on current main.** The starter prompts A first (guides/patterns/debate.md:175). On A’s `max_rounds` turn, `handle_response/3` records its text locally but sends B only `{:debate, :done}`; text is sent only on earlier turns (guides/patterns/debate.md:113, guides/patterns/debate.md:119, guides/patterns/debate.md:124). B halts on `:done` without a response (guides/patterns/debate.md:142). Thus B produces one fewer turn than A, and at `max_rounds: 1` produces none. The guide’s “both halt together” description does not mean both reach the cap (guides/patterns/debate.md:58).

### Debate guide has no handle_error; one failed turn leaves both agents idle and un-halted indefinitely

`Debate.Agent` does not override `handle_error/3`. The default returns `{:noreply, state}`, so a backend error, watchdog timeout or interrupt on either side ends that turn without notifying the opponent. Neither agent halts and nothing signals the caller. Pipeline and Supervisor both propagate failure; Debate does not.

**Verification on current main.** The callback recipe defines no `handle_error/3` (guides/patterns/debate.md:74-148), so it inherits `{:noreply, state}` (lib/gen_agent.ex:415-416). On a failed turn, that decision returns the active agent to idle without halting (lib/gen_agent/server.ex:1304-1334). The recipe notifies the opponent only after a successful response (guides/patterns/debate.md:112-128), leaving the exchange stalled if no new input arrives. Its starter uses `tell/3`, which sends no completion message; the caller can still discover that turn’s error with `poll/3` (guides/patterns/debate.md:175-179; lib/gen_agent.ex:660-675).

### Debate guide's "interleaved transcript" is two disjoint per-agent lists

The usage block is labelled "Read the interleaved transcript" and then reads `transcript` from each agent separately. Each agent appends only its own turns, so neither list is interleaved and the opponent's statements are not stored anywhere on state.

**Verification on current main.** The callback recipe appends only `{state.name, text}` to the responding agent’s `transcript` (guides/patterns/debate.md:113). Receiving `{:opponent_said, text}` creates a prompt and returns the state unchanged, so the opponent’s statement is not added to that list (guides/patterns/debate.md:132). The usage block labels the result “interleaved” but reads `transcript_a` and `transcript_b` separately, without combining them (guides/patterns/debate.md:203).

## Acceptance

- Tests cover each case above.

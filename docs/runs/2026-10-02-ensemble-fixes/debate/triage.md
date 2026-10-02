I’ll inspect the current Debate strategy, its tests, and direct docs, then map each finding claim to the present code and give a minimal fix plan without changing files.

At **HEAD `7f848d4`**, the finding still holds. The repository already has a test that confirms the raw-response behavior; the fix is not present.

### Claims that still hold

- **The first agent receives the caller’s prompt unchanged.** `start_or_queue/3` dispatches `prompt` directly to `state.first` at [debate.ex:113-115](/private/tmp/gen_agent_fix_212_20261002/extensions/ensemble/lib/gen_agent_ensemble/strategies/debate.ex:113).
- **Later turns receive only the previous response text.** `advance/6` dispatches `response.text` to the other agent at [debate.ex:142-145](/private/tmp/gen_agent_fix_212_20261002/extensions/ensemble/lib/gen_agent_ensemble/strategies/debate.ex:142). The strategy state and options have no saved original prompt or speaker-framing function; see [debate.ex:50-61](/private/tmp/gen_agent_fix_212_20261002/extensions/ensemble/lib/gen_agent_ensemble/strategies/debate.ex:50) and [debate.ex:63-102](/private/tmp/gen_agent_fix_212_20261002/extensions/ensemble/lib/gen_agent_ensemble/strategies/debate.ex:63).
- **The strategy does not label the previous speaker or repeat the caller’s question on later turns.** Its module documentation describes response text becoming the next prompt at [debate.ex:6-10](/private/tmp/gen_agent_fix_212_20261002/extensions/ensemble/lib/gen_agent_ensemble/strategies/debate.ex:6). The workflow guide also documents the raw-response wire format at [debate.md:25-29](/private/tmp/gen_agent_fix_212_20261002/extensions/ensemble/guides/workflows/debate.md:25).
- **An existing test codifies this behavior.** It expects the second agent to receive `"a:x1"` and the first agent’s next turn to receive `"b:y1"` at [debate_test.exs:66-94](/private/tmp/gen_agent_fix_212_20261002/extensions/ensemble/test/gen_agent_ensemble/strategies/debate_test.exs:66).

### Already resolved

None of the reported prompt-context or speaker-label issues appear resolved. The current code does preserve the first-turn prompt exactly, checks convergence against the raw response text from turn two onward, and keeps queued prompts in `Queue` until starting a new run at [debate.ex:113-119](/private/tmp/gen_agent_fix_212_20261002/extensions/ensemble/lib/gen_agent_ensemble/strategies/debate.ex:113) and [debate.ex:177-188](/private/tmp/gen_agent_fix_212_20261002/extensions/ensemble/lib/gen_agent_ensemble/strategies/debate.ex:177). Those behaviors should remain intact in the fix.

### Smallest change plan

- **`extensions/ensemble/lib/gen_agent_ensemble/strategies/debate.ex`**: retain each run’s original prompt and, when dispatching a later turn, construct the prompt from that original question plus the previous speaker’s name and response text. Keep the initial dispatch unchanged; leave convergence checks and transcript/reply construction operating on the original response text. Ensure a queued run initializes its own original prompt when it starts.
- **`extensions/ensemble/test/gen_agent_ensemble/strategies/debate_test.exs`**: replace the raw-response expectations with behavioral assertions that capture actual prompts for both agents: exact unchanged prompt on turn one, question and prior-speaker label on later turns, and no prompt leakage between two queued debates. Preserve the existing convergence and reply-shape coverage.
- **`extensions/ensemble/guides/workflows/debate.md`** and **the strategy module documentation in `debate.ex`**: update the prompt-flow description and example to reflect that later-turn prompts retain the caller’s question and identify the previous speaker. No broad prompt-configuration API is needed.

No files were edited.
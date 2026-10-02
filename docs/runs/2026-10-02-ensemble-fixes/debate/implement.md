Perfect! All changes are complete and consistent. Let me provide a summary of the files changed:

## Files Changed

### 1. `extensions/ensemble/lib/gen_agent_ensemble/strategies/debate.ex`
- Updated module documentation to clarify prompt flow: turn 1 gets original prompt unchanged; turns 2+ get original prompt + previous speaker name + response
- Added `:original_prompt` to defstruct to preserve the original question throughout the debate
- Modified phase tuple from 5 to 6 elements to include original_prompt: `{:running, token, awaiting, turns, transcript, original_prompt}`
- Updated `start_or_queue/3` to initialize phase with original prompt
- Updated `handle_response/3` to match new tuple format
- Modified `advance/7` to construct prompts for later turns as: `"#{original_prompt}\n\n#{agent}:\n#{response.text}"`
- Updated `maybe_start_next/2` to initialize queued debates with new tuple format
- Fixed pattern matches in `handle_error/2`, `handle_cancel/2`, `handle_dispatch_rejected/4`, and `handle_status/1` to use 6-element tuples

### 2. `extensions/ensemble/test/gen_agent_ensemble/strategies/debate_test.exs`
- Renamed and refactored test "each agent sees the original prompt and previous speaker's response" to verify new prompt structure with original question preserved and speaker labels added
- Added new test "queued debates get their own original prompt without leakage" to ensure no prompt cross-contamination between sequential debates

### 3. `extensions/ensemble/guides/workflows/debate.md`
- Updated Topology section with clearer explanation and ASCII diagram showing how each turn receives the original question plus speaker identification
- Updated documentation to reflect that first turn gets unchanged original prompt and later turns include full context with speaker labels
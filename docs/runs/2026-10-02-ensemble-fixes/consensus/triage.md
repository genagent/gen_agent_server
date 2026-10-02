I’ll keep this review read-only and check the current strategy, tests, and direct docs.


Both findings still hold on local `main` and `HEAD`, both at `7f848d4`. Neither is resolved. The working tree is clean.

- **Arbitrary tied verdict:** [consensus.ex:126](/private/tmp/gen_agent_fix_209_20261002/extensions/ensemble/lib/gen_agent_ensemble/strategies/consensus.ex:126) accepts thresholds from 1 through N. At line 221, `Enum.max_by/3` selects one maximum without detecting ties; line 303 labels it `CONSENSUS`. A 2–2 split with `{:at_least, 2}` therefore converges incorrectly. This finding does not depend on the precise OTP atom-order behavior.
- **Premature error:** [consensus.ex:355](/private/tmp/gen_agent_fix_209_20261002/extensions/ensemble/lib/gen_agent_ensemble/strategies/consensus.ex:355) still unconditionally fails the token on the first turn error. Unparseable responses instead abstain at line 174. [server.ex:799](/private/tmp/gen_agent_fix_209_20261002/extensions/ensemble/lib/gen_agent_ensemble/server.ex:799) removes completed tokens from pending; its response guard at line 462 ignores subsequent responses. The heterogeneous-backend use case remains documented at [consensus.md:192](/private/tmp/gen_agent_fix_209_20261002/extensions/ensemble/guides/workflows/consensus.md:192).
- **Coverage remains insufficient:** [consensus_test.exs:154](/private/tmp/gen_agent_fix_209_20261002/extensions/ensemble/test/gen_agent_ensemble/strategies/consensus_test.exs:154) tests only an untied `at_least` result. The error test at line 266 covers unanimity, where failing is appropriate.

Smallest proposed change:

1. **`extensions/ensemble/lib/gen_agent_ensemble/strategies/consensus.ex`**
   - Require a **unique highest count** meeting the threshold. Tied leaders continue deliberation or diverge at the cap. Preserve existing unequal-count successes, including when two categories exceed a low threshold.
   - Record failed turns as completed abstentions, retaining original `{agent, reason}` evidence separately for the current round.
   - After each response or error, calculate threshold reachability using the fixed panel size: required votes are N, `div(N, 2) + 1`, or n. If errors exist and `largest current vote count + outstanding turns < required votes`, fail using an original error tuple. Otherwise wait for remaining turns and apply normal round completion. Error-free disagreement retains its existing retry/divergence behavior.
   - Keep tied qualifying results as nonconvergence, not provider failure. Reset error tracking between rounds and runs, including cancellation and queued starts. Preserve synthesis fields and response tuple shapes; represent tolerated errors with nil verdicts, explanatory rationales, and empty raw text. Update module documentation accordingly.

2. **`extensions/ensemble/test/gen_agent_ensemble/strategies/consensus_test.exs`**
   - Add deterministic behavioral coverage for tied thresholds, reordered arrivals and agent lists, unequal qualifying counts, tie resolution next round, and cap divergence.
   - Cover errors arriving before/after votes, multiple tolerated errors, impossibility discovered by either an error or a later response, all threshold types, and original error preservation.
   - Cover round-local reset, queued runs after success/failure, late previous-token responses, and unchanged custom synthesis shape. Retain the unanimous failure test.

3. **`extensions/ensemble/guides/workflows/consensus.md`**
   - Explain unique-leader convergence, fixed thresholds despite errors, tolerated failed turns, explicit impossibility failure, and round-local retries.

No files edited, tests run, or network commands executed. Package tests and quality gates remain with the caller.
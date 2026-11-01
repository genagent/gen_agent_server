I've finished reading `run.ex`, `query.ex`, `error.ex` and the tests. All seven earlier items are resolved, and item 6 is declined with documentation. I found no blocking defects in the two new commits. I couldn't run anything, so pass or fail for the tests is still for the operator to confirm.

## Earlier items

1. **Resolved.** The outcome is now reported from inside the exec span, before the stop handlers run (`query.ex:1229`, `run.ex:382-383`). The worker sends that message before its own exit, so the run process sees the outcome first. The worker-exit clause at `run.ex:444` then ignores the exit. The test is at `run_test.exs:227`.
2. **Resolved.** Exit signals are handled at `run.ex:449-454`. A `:normal` signal is ignored. Any other reason cancels the run and stops the run process with that reason (`stop_reason` is used at `run.ex:557`). Tests are at `run_test.exs:411` and `:431`.
3. **Resolved.** `release/1` is at `run.ex:241` and `run.ex:402-405`. Tests are at `run_test.exs:441` and `:451`.
4. **Resolved.** The run process now sends a not-started record when it fails to start (`run.ex:208-212`, `run.ex:289-299`). It has no test because the path can't be reached.
5. **Resolved.** Both reasons are now documented at `error.ex:48-51` and `run.ex:101-106`.
6. **Declined, and the decline is documented** at `runner.ex:99-100`, `collector.ex:35-36` and `forcola_evidence.ex:175-177`. That is acceptable.
7. **Resolved.** The `snapshot/2` timeout guard is at `run.ex:224`, and `collector.ex` has been reflowed. A new over-long line appeared; see defect 1.

The three confirmation-review fixes are also in place:
- **P1 (worker outliving release or owner exit):** `terminate/2` ends the execution process (`run.ex:492-495`), and the cancel-grace handler ends it without a status check (`run.ex:459-462`). Tests are at `run_test.exs:261` and `:276`.
- **P2 (caller exit on an arbitrary stop reason):** the catch-all at `run.ex:285-286` returns `:not_found`. The test is at `run_test.exs:303`.
- **P2 (`release/1` returning `:timeout`):** `release/1` is now a cast, which always returns `:ok`.

## 1. Acceptance

- **`start/3` validates options before spawning: met.** See `run.ex:190-192`, and `query.ex:1145-1153` for the not-started record. Test at `run_test.exs:499`.
- **Frames arrive in order and the mailbox policy is documented: met.** Docs at `run.ex:54-64`, delivery at `run.ex:589-598`, test at `run_test.exs:31`.
- **`snapshot/1` does not block on the child: met.** It answers from the run process's own state (`run.ex:387`). Test at `run_test.exs:114`.
- **`await/2` returns the same categories plus one record, and its timeout does not cancel: met.** See `run.ex:248-278` and `run.ex:529-558`. Tests at `run_test.exs:31`, `:80` and `:96`.
- **`cancel/2` is idempotent, records the cancellation and reports cleanup facts: met.** See `run.ex:389-397` and `run.ex:521-527`. Tests at `run_test.exs:129`, `:170` and `:178`.
- **Owner exit cancels the run: met.** See `run.ex:467-473`. Test at `run_test.exs:198`.
- **Fake-executable tests for every listed case: met.** Success and failure (`:31`, `:80`), timeout (`:96`, `:105`), cancel before output (`:129`), cancel after output (`:153`), owner exit (`:198`).

## 2. Defects (all minor)

1. **`error.ex:52` is an over-long line that `mix format` won't reflow.** It is the same problem item 7 was about. Fix: rewrap lines 51-54 by hand.
2. **The `:cancelled` entry at `error.ex:42-44` is now incomplete.** It lists only `cancel/2` and owner exit. As of `run.ex:451-452`, a non-`:normal` exit signal also produces `:cancelled`. Fix: add "or by a non-normal exit signal to the run process".
3. **`send_not_started` (`run.ex:289-297`) rebuilds the evidence record by hand instead of using Query's version (`query.ex:1388-1404`).** It leaves out `result:`. That is harmless here, because the stdout is empty and the result is nil. But the two copies can drift apart. Fix: expose a `@doc false` `Query.send_not_started/3` (or reuse `reject_not_started/3`) and call it from `Run`.
4. **The test at `run_test.exs:227` depends on timing.** The 300 ms cancel grace starts when the cancel is requested. If the test process is slow to send `:go` after `wait_until`, the grace kills the worker before the runner returns. The outcome then becomes `:cancelled` and the test fails. Fix: use a larger `cancel_grace_ms` (for example 2_000), so the gap that matters is the telemetry block, not scheduling between the cancel and `:go`.
5. **`run.ex:87` is a short ragged line left over from the doc edit.** This is cosmetic. Fix: reflow the paragraph.

## 3. Changes beyond the issue

- **`release/1`, exit-signal handling and `terminate/2`** go beyond the issue. They came from the review, are documented and tested, and should stay.
- **The `:report` hook in `Query.run_prepared/2`** is internal (`@doc false`) and is needed for item 1. It should stay.
- **The doc notes in `runner.ex`, `collector.ex` and `forcola_evidence.ex`** document the item 6 decline. They should stay.

APPROVE

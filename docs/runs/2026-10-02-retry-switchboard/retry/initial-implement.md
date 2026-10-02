I changed the retry guide and added a test file, but I couldn't run any tests. Every `mix` command was blocked for approval in this session, so the new tests have not been compiled or run. I also didn't run `mix format`, so the test file may need formatting.

Files changed:
- `guides/patterns/retry.md`: rewritten around a timer-based retry.
  - **Backoff:** `handle_error/3` no longer calls `Process.sleep/1`. It schedules the retry with `:timer.apply_after` and `GenAgent.notify/2`, stores a token on state, and returns `{:noreply, state}`. `handle_event/2` returns the retry prompt only when the pending token matches.
  - **Cancel safety:** a stale token is ignored. `:cancel_retry` cancels the timer and halts with phase `:cancelled`. `terminate_agent/2` cancels any pending timer.
  - **Interrupt and watchdog:** `:interrupted` and `:timeout` now halt (phases `:interrupted` and `:timed_out`) instead of retrying.
  - **New start options:** `init_agent/1` now takes `:agent_name`, which has to repeat the agent's `:name` because GenAgent strips `:name` before calling `init_agent/1`. It also takes `:base_backoff_ms` (default 1000) and `:backend_opts` (forwarded to the backend).
  - **Testing section:** replaced with a runnable local stub, `Retry.FlakyBackend`, that needs no credentials or network.
  - **Prose:** Variations and the intro text are updated to match.
- `test/guides/retry_test.exs` (new): compiles `Retry.Agent` and `Retry.FlakyBackend` directly from the guide and covers:
  - **Callbacks:** non-blocking scheduling, doubling backoff, halting on `:interrupted` and `:timeout`, the attempt cap, and token matching.
  - **Runtime:**
    - retry through failures to success;
    - give-up at the cap;
    - `status/1` responsive during backoff, with cancel preventing the retry;
    - `GenAgent.stop/1` during a 60 s backoff finishing promptly with `terminate_session` called;
    - `interrupt/1` and a watchdog timeout each not triggering a retry.

Please run `mix format` and `mix test test/guides/retry_test.exs`.

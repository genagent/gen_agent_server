I’ll read the guide, tests, and runtime paths to verify the behavior and scope, then try the focused checks available in this read-only session.


The runtime confirms that interruption and watchdog timeout halt an active attempt. During backoff, though, the server is idle, so `interrupt/1` is ignored and the timer still retries. The guide needs to make that distinction explicit.

The focused test command cannot run because dependencies are missing. The read-only formatting check ran and found formatting failures in the new test file.


REQUEST CHANGES

- **P2 — guides/patterns/retry.md:30:** Clarify that `interrupt/1` does **not** cancel backoff. The server ignores interrupts while idle (`lib/gen_agent/server.ex:653`), so interrupting during `:waiting` still allows another attempt. Explicitly document the required `:cancel_retry` event and add a runtime test covering interruption during backoff.

- **P2 — test/guides/retry_test.exs:79:** “backoff doubles per attempt” only asserts that a timer exists, then cancels it. A constant or zero delay would pass. Verify actual delay progression using the guide module, with tolerances suitable for runtime scheduling.

- **P2 — test/guides/retry_test.exs:101:** Cancellation coverage never delivers the original timer token after cancellation. Add a runtime test injecting that stale notification after cancellation and verify that no prompt starts; cancelling the timer before it fires does not exercise the delivery race.

- **P2 — test/guides/retry_test.exs:71:** `mix format --check-formatted test/guides/retry_test.exs` fails. Format the file before merging.

Scope is limited to the requested guide and tests. The focused test run was blocked by missing dependencies (`telemetry`, `dialyxir`, and `credo`), so compilation and test success remain unverified.
I’ll inspect the invocation and remote command paths, add result waiting and tests, then run the required checks.


The invocation store already polls while work is pending. I’ve added deferred replies there so waiting callers leave the GenServer free to serve other requests. Completion will reply to every waiter for the ID, and each wait has its own timer.


The new waiter tests pass. The root run has seven failures caused by Mix’s sandbox TCP warning appearing in subprocess output that tests expect to be clean. Credo and docs tasks are unavailable in this project. I’m checking the extension matrix and adding a regression test for the remote ops timeout.


The extension matrix caught a control test that uses the original internal result request tuple; I’ve preserved that request form. MCP’s schema test now expects optional `wait_ms`. The remote ops regression verifies that a 600,000 ms wait gets a 630,000 ms RPC timeout.


The final root run passed 117 of 124 tests; the seven failures are from sandbox TCP warnings in subprocess output. MCP passed 32 of 33, with its HTTP socket test blocked by `:eperm`. Control passed all 88 after the compatibility fix. Selection, public_source, and schedule passed; patterns and peers have sandbox-related failures. Format and warnings-as-errors compilation passed.


Implemented `GenAgentServer.result(instance, id, wait_ms: ms)` with validation, deferred replies, multiple waiters, and timeout cleanup. Existing result calls remain immediate. Added ops/MCP `wait_ms`, CLI `result ID --wait MS`, remote RPC margins, and README documentation.

Changed 11 files: README; `gen_agent_server.ex`; invocation, ops, CLI, and remote modules; the ops Mix task; three root test files; and the MCP schema test. Tests cover terminal outcomes, cancellation, expiry, concurrent calls, validation, multiple waiters, schemas, and RPC timeouts.

Checks run:all Mix commands used `MIX_OS_CONCURRENCY_LOCK=0`:

| Command | Result |
|---|---|
| `mix format` | Passed, root and MCP |
| `mix format --check-formatted` | Passed, root and all extensions |
| `mix compile --warnings-as-errors` | Passed, root and all extensions |
| `mix test`: root | 117/124 passed |
| `mix test`: MCP | 32/33 passed |
| `mix test`: other extensions | control 88/88; selection 8/8; public_source 7/7; schedule 5/5; patterns 16/17; peers 0/19 |
| `mix test test/gen_agent_server_cancellation_test.exs test/gen_agent_server_result_rpc_test.exs test/gen_agent_server_remote_test.exs` | 25/25 passed |
| `mix credo --strict` / `mix docs` | Tasks unavailable |
| `git diff --check` | Passed |

The remaining test failures stem from sandbox TCP warnings or blocked sockets (`:eperm`). Full acceptance remains subject to the authoritative host run. Credo and generated docs could not be checked because their tasks are absent; no dependencies were fetched.

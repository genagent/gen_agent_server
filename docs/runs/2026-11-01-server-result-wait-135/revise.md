I’ll fix all five defects, keep and comment the two-element result request clause, then rerun the requested checks.


All five fixes are in place. Shared MCP now caps result waits at 5 seconds; the catalogue publishes the 600-second limit; CLI messages cover `--wait`; result options reject malformed and unknown keys; and expiry drains completions before returning pending. I’ve added regression tests and am running the requested checks.


Fixed all five defects and added regression tests:

1. Shared MCP caps `wait_ms` at 5000 in its schema and runtime validation.
2. The operations catalogue publishes the 600,000 maximum; MCP tests assert it.
3. Both CLI usage strings include `[--wait MS]`; invalid waits have a clear message, and missing IDs name the invocation.
4. `result/3` returns `{:error, :invalid_options}` for non-keyword options or unknown keys.
5. Wait expiry collects inbox completions before replying pending and handles inbox errors like polling does.

Kept the two-element result request clause and added the requested compatibility comment.

Checks run:

- `MIX_OS_CONCURRENCY_LOCK=0 mix format`: passed in root and MCP.
- `MIX_OS_CONCURRENCY_LOCK=0 mix compile --warnings-as-errors`: passed.
- `MIX_OS_CONCURRENCY_LOCK=0 mix test`: root: 120/127 passed; seven sandbox warning failures.
- `MIX_OS_CONCURRENCY_LOCK=0 mix test` in `extensions/mcp`: 33/34 passed; one socket test blocked by sandbox `:eperm`.
- `git diff --check`: passed.

All new regression tests passed.

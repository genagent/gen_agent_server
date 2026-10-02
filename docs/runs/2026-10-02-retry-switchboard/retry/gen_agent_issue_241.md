Found by the 2026-10-01 review at `b8f8ab4` and re-verified against `main` at `1a03608` by a read-only Codex worker in a `gen_agent_server` verification pool (genagent/gen_agent_server#25). One verifier per finding: treat file and line references as the starting point for the fix, and re-check them.

## Problem

### Retry guide backoff sleeps inside handle_error/3 and blocks the agent process

Retry.Agent calls Process.sleep/1 inside handle_error/3, which runs in the agent's :gen_statem process. During the sleep the agent cannot answer status/poll/interrupt/stop. With the guide's own usage (max_attempts: 5) the fourth backoff is 8 s, longer than the 5 s child shutdown, so GenAgent.stop/1 during that sleep ends in a brutal kill and terminate_agent/2 and Backend.terminate_session/1 never run.

**Verification on current main.** `Retry.Agent.handle_error/3` sleeps before returning a retry decision (guides/patterns/retry.md:83). The server calls that callback in its own `:gen_statem` process, so it cannot handle status, poll, or interrupt messages during the sleep (lib/gen_agent/server.ex:1304). With `max_attempts: 5`, the fourth failure sleeps `2^(4−1) × 1000 = 8,000` ms (guides/patterns/retry.md:89, guides/patterns/retry.md:106). The child’s shutdown timeout is 5,000 ms; `stop/1` asks the supervisor to terminate it (lib/gen_agent/server.ex:78, lib/gen_agent.ex:861). A stop begun early in that sleep can therefore force-kill the process before its termination callbacks run (lib/gen_agent/server.ex:175).

### Retry guide retries every error reason, so interrupt/1 and watchdog timeouts trigger another attempt

Retry.Agent.handle_error/3 has a single clause that retries any reason. GenAgent.interrupt/1 delivers :interrupted to handle_error/3, so interrupting a Retry agent causes a sleep and a new attempt instead of stopping work. The guide only mentions error classification under Variations.

**Verification on current main.** `Retry.Agent.handle_error/3` has one clause for every reason. Below the attempt cap, it sleeps and returns a new prompt regardless of the reason (guides/patterns/retry.md:83-99). Both `interrupt/1` and the watchdog call that error path with `:interrupted` and `:timeout`, respectively (lib/gen_agent/server.ex:431-438,493-500). Thus either can start another attempt until the cap is reached. The guide discusses excluding those reasons only under “Error-class-aware retry” in Variations (guides/patterns/retry.md:159-168).

### Retry guide testing section does not work with the guide's own module

The guide says to pass `http_fn: failing_http_fn(2)` in the start opts, but Retry.Agent.init_agent/1 builds backend opts from :system and :max_tokens only, so :http_fn never reaches the Anthropic backend and the real HTTP client is used. The snippet is also a bare `defp` that calls an undefined `canned_success_response/1`, and it refers to a playground that is not in this repository.

**Verification on current main.** `Retry.Agent.init_agent/1` forwards only `:system` and `:max_tokens` to the backend, so the suggested `http_fn` start option is dropped (guides/patterns/retry.md:53, guides/patterns/retry.md:155). Anthropic then selects its default HTTP function, which uses `Req.post/2` (integrations/anthropic/lib/gen_agent/backends/anthropic.ex:89, integrations/anthropic/lib/gen_agent/backends/anthropic.ex:231). The testing snippet is a standalone `defp` and calls `canned_success_response/1`, which it never defines (guides/patterns/retry.md:136). It refers to a playground, but none is present in the repository (guides/patterns/retry.md:129).

## Acceptance

- Tests cover each case above.

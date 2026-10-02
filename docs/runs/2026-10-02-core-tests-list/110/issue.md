# test: make eight core tests assert what their names state

Found in a read-only review of `main` at `b8f8ab4`. Code links point at that commit; `main` has moved since (core 0.4.0).

## Current state

Eight core tests pass under mutations that break the behaviour in their names. Verified by mutation: (1) running post_turn/3 before handle_response/3 and (2) sending the original, unrewritten prompt to Backend.prompt/2 while telemetry reports the rewritten one both pass the full core suite (160 passed), so post_turn ordering and pre_turn prompt rewriting at the backend are untested. (3) Deleting the `use GenAgent` default handle_error/3 and handle_event/2 and (4) stamping every Event with timestamp 0 also pass the full suite, because server.ex:958 and :1244 fall back via function_exported?/3, server_test.exs:681 runs TestAgent (own handle_error/3, no `use GenAgent`), and event_test.exs:23 uses `>=`. [`test/scenarios/checkpointer_scenario_test.exs:178-180`](https://github.com/genagent/gen_agent/blob/b8f8ab4/test/scenarios/checkpointer_scenario_test.exs#L178-L180) has a comment in place of an assertion (Mock.remaining is 1 today, so the assertion would pass). lifecycle_hooks_test.exs:69-92 and :239-261 use order-insensitive `assert_received` pairs; for pre_run the sibling test at :53-67 gives partial coverage (it fails if pre_run does not fire on its own after init), so only the named test is ineffective there. [`test/gen_agent_test.exs:4-6`](https://github.com/genagent/gen_agent/blob/b8f8ab4/test/gen_agent_test.exs#L4-L6) is a trivially true `Code.ensure_loaded?(GenAgent)` check (not the verbatim `mix new` placeholder). Fix: assert order by recording callbacks in agent state or by reading the mailbox in sequence; assert `Mock.history(:gen_statem.call(pid, :get_backend_session)) == ["[prefix] hello"]` in the rewrite test; assert `Mock.remaining(session) == 1` in the checkpointer test; test the macro defaults directly (for example `function_exported?(SimpleAgent, :handle_event, 2)` and calling the generated functions); change the event test to `>` or drop it; delete test/gen_agent_test.exs.

**Evidence.** [`test/gen_agent/lifecycle_hooks_test.exs:69-92`](https://github.com/genagent/gen_agent/blob/b8f8ab4/test/gen_agent/lifecycle_hooks_test.exs#L69-L92) "fires before any prompt dispatches" and :239-261 "runs between decision callback and transition" use two `assert_received` selective matches, which pass in either order. :139-155 ":ok can rewrite the prompt" asserts only that pre_turn saw "hello"; the comment at 147-149 defers to the telemetry test and nothing checks Mock.history. [`test/scenarios/checkpointer_scenario_test.exs:178-180`](https://github.com/genagent/gen_agent/blob/b8f8ab4/test/scenarios/checkpointer_scenario_test.exs#L178-L180) ends with the comment "The second script should NOT have been consumed." and no assertion. [`test/gen_agent/integration_test.exs:453-464`](https://github.com/genagent/gen_agent/blob/b8f8ab4/test/gen_agent/integration_test.exs#L453-L464) "provides default handle_event that keeps state" asserts only `state == :idle`, which also holds with no default because server.ex:958 falls back via function_exported?/3. [`test/gen_agent/server_test.exs:681-693`](https://github.com/genagent/gen_agent/blob/b8f8ab4/test/gen_agent/server_test.exs#L681-L693) "default handle_error is {:noreply, state} (via use GenAgent)" runs TestAgent, which declares `@behaviour GenAgent` and its own handle_error/3 ([`test/support/test_agent.ex:20`](https://github.com/genagent/gen_agent/blob/b8f8ab4/test/support/test_agent.ex#L20), 89-94). [`test/gen_agent_test.exs:4-6`](https://github.com/genagent/gen_agent/blob/b8f8ab4/test/gen_agent_test.exs#L4-L6) is the `mix new` placeholder. [`test/gen_agent/event_test.exs:18-24`](https://github.com/genagent/gen_agent/blob/b8f8ab4/test/gen_agent/event_test.exs#L18-L24) asserts `e2.timestamp >= e1.timestamp`, true for any two monotonic readings.

**Scenario.** If pre_run/1 ran after the first dispatch, or post_turn/3 ran before handle_response/3, or pre_turn's rewritten prompt were dropped before reaching Backend.prompt/2 while telemetry still reported it, these tests would still pass.

Reproduction from the review (private checkout, stub backend or fake CLI, no provider called):

```text
Mutation A (lib/gen_agent/server.ex):
- finish_turn/5: call safely_post_turn(module, {:ok, response}, ref, new_agent_state) first, then handle_response(ref, response, pre_hooked).
- dispatch/5: pass `original_prompt || prompt` instead of `prompt` to run_prompt (telemetry unchanged).
Result: `mix test test/gen_agent/lifecycle_hooks_test.exs` -> 23 passed; `mix test` -> 160 passed.

Mutation B:
- lib/gen_agent.ex __using__: delete default handle_error/3 and handle_event/2 and their defoverridable entries.
- lib/gen_agent/event.ex: `timestamp: 0`.
Result: `mix test` -> 160 passed.

Mutation C (server.ex): init returns `{:ok, :idle, data}` (no :pre_run next_event); finish_turn runs safely_pre_run after handle_response when pre_run_done is false.
Result: lifecycle_hooks_test 20/23 passed; "fires before any prompt dispatches" (:69) passed; failures were :53, the :pre_run_failed test and the :pre_run_crashed test.

Probes on unmodified lib:
- checkpointer "finish" test: `session = :gen_statem.call(GenAgent.whereis(name), :get_backend_session); {Mock.remaining(session), Mock.history(session)}` -> {1, ["start"]}
- rewrite test: `Mock.history(:gen_statem.call(pid, :get_backend_session))` -> ["[prefix] hello"]
- post_turn ordering test: `Process.info(self(), :messages)` -> [ordering: :handle_response, ordering: :post_turn]
```

## Desired state

- Assert order by receiving in sequence with pinned messages (`assert_receive {:ordering, :pre_run}` then check the next mailbox message) or by recording a list in agent state. Assert the backend prompt with a function script that sends the prompt to the test process. Assert `Mock.remaining/1 == 1` in the checkpointer test. Delete the placeholder test.

## Acceptance

- The change is in place and `scripts/quality.sh` passes for the affected package.

## Verification

- Confirmed by an independent code trace and reproduced by running code.


https://github.com/genagent/gen_agent/issues/110

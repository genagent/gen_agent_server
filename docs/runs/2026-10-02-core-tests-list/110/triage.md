I’ll keep this to a read-only check of the eight tests and the code paths they exercise.


Seven of the eight gaps remain in the named tests. The checkpointer test has been replaced: it now checks that no further backend turn starts, so the old comment-only claim is resolved.


At checkout `abb0338`, **seven named-test gaps remain; the checkpointer case is resolved.** This was a static code review. No files changed; tests and mutations were not run.

| Case | Current finding |
|---|---|
| `pre_run` ordering | **Still holds.** [lifecycle_hooks_test.exs:69](/private/tmp/gen_agent_issue_110_20261002/test/gen_agent/lifecycle_hooks_test.exs:69) uses two selective `assert_received` matches at lines 90–91. These permit either order and observe response handling rather than dispatch. The sibling test at line 52 still provides partial coverage. |
| Prompt rewriting | **Still holds.** [lifecycle_hooks_test.exs:139](/private/tmp/gen_agent_issue_110_20261002/test/gen_agent/lifecycle_hooks_test.exs:139) only checks that the hook received `"hello"`. Nothing asserts what the backend received. |
| `post_turn` ordering | **Still holds.** [lifecycle_hooks_test.exs:239](/private/tmp/gen_agent_issue_110_20261002/test/gen_agent/lifecycle_hooks_test.exs:239) retains order-insensitive matches at lines 259–260 and does not observe the transition boundary. |
| Checkpointer finish | **Resolved.** [checkpointer_scenario_test.exs:156](/private/tmp/gen_agent_issue_110_20261002/test/scenarios/checkpointer_scenario_test.exs:156) now asserts one completed draft, halted status, and no additional `{:turn, _, _}` message. Its replacement backend announces every invocation at line 36; it no longer uses Mock scripts. Adding `Mock.remaining/1` is obsolete. |
| Macro default `handle_event/2` | **Still holds.** [integration_test.exs:455](/private/tmp/gen_agent_issue_110_20261002/test/gen_agent/integration_test.exs:455) checks only idle status after a sleep. The missing-callback fallback remains at [server.ex:1523](/private/tmp/gen_agent_issue_110_20261002/lib/gen_agent/server.ex:1523). |
| Macro default `handle_error/3` | **Still holds.** [server_test.exs:736](/private/tmp/gen_agent_issue_110_20261002/test/gen_agent/server_test.exs:736) still exercises TestAgent’s own implementation at [test_agent.ex:90](/private/tmp/gen_agent_issue_110_20261002/test/support/test_agent.ex:90). The server fallback also remains at line 1858. |
| Placeholder | **Still holds.** [gen_agent_test.exs:4](/private/tmp/gen_agent_issue_110_20261002/test/gen_agent_test.exs:4) only checks module availability. |
| Event timestamp | **Still holds.** [event_test.exs:18](/private/tmp/gen_agent_issue_110_20261002/test/gen_agent/event_test.exs:18) sleeps, then asserts `>=`; constant timestamps pass. |

Smallest focused change: five test files.

- **`test/gen_agent/lifecycle_hooks_test.exs`:** Have `pre_run` put a marker in state and `pre_turn` report the marker it sees before dispatch. Use a Mock function script to send the actual rewritten prompt to the test and assert `"[prefix] hello"`. For `post_turn`, accumulate callback order in state; choose a halt transition and have `post_run` report the trace, asserting `[:handle_response, :post_turn, :post_run]`. This covers both boundaries without sleeps or selective-receive ordering mistakes.
- **`test/gen_agent/integration_test.exs`:** Replace the sleeping default-event test with direct calls to SimpleAgent’s generated callbacks. Assert both callbacks are exported and both return `{:noreply, ^state}` for a nonempty state.
- **`test/gen_agent/server_test.exs`:** Rename the existing error-recovery test to describe TestAgent recovery and remove its misleading macro-default comment. Keep its useful recovery assertions.
- **`test/gen_agent/event_test.exs`:** Replace the sleep/pair comparison with an event timestamp bounded by `System.monotonic_time(:millisecond)` readings immediately before and after construction.
- **`test/gen_agent_test.exs`:** Delete it.

Leave the checkpointer scenario, production code, Ensemble, and pattern guides untouched. Validate the affected tests, check sensitivity to the reported mutations, then run the core-package checks listed in [scripts/quality.sh:11](/private/tmp/gen_agent_issue_110_20261002/scripts/quality.sh:11). The script currently loops over every package; it has no package-selection argument.
I’m checking the current Supervisor path, its tests, and the guide against the issue’s acceptance criteria.

**Confirmed on current code**

- The strategy has no fan-out limit. [`supervisor.ex`](/private/tmp/gen_agent_issue_214_20261002c/extensions/ensemble/lib/gen_agent_ensemble/strategies/supervisor.ex:108) passes the coordinator’s text to the decomposer; lines 112–123 build start and dispatch operations for every returned prompt.
- The guide still shows newline splitting, with no limit configured or documented: [`supervisor.md`](/private/tmp/gen_agent_issue_214_20261002c/extensions/ensemble/guides/workflows/supervisor.md:91).
- The focused tests cover multi-worker fan-out, empty decomposition, and queued work, but not a limit, an over-limit error, or invalid limit options: [`supervisor_test.exs`](/private/tmp/gen_agent_issue_214_20261002c/extensions/ensemble/test/gen_agent_ensemble/strategies/supervisor_test.exs:42).

**Already supported**

- Empty decomposition replies with the coordinator’s text, and queued work advances through `maybe_prepend_next`: [`supervisor.ex`](/private/tmp/gen_agent_issue_214_20261002c/extensions/ensemble/lib/gen_agent_ensemble/strategies/supervisor.ex:124), lines 173–188. The empty case is tested; queued fan-out is tested at [`supervisor_test.exs`](/private/tmp/gen_agent_issue_214_20261002c/extensions/ensemble/test/gen_agent_ensemble/strategies/supervisor_test.exs:158).
- The Server supports caller-visible `:reply_error` operations ([`server.ex`](/private/tmp/gen_agent_issue_214_20261002c/extensions/ensemble/lib/gen_agent_ensemble/server.ex:667)) and starts children through `DynamicSupervisor.start_child` (line 613). The issue’s proposed fix can stay at the strategy boundary.

**Smallest change plan**

- In `supervisor.ex`, add a documented positive `:max_subtasks` option with a conservative default; validate it during `init`. Check the decomposer result’s count before building any worker operations. If it exceeds the limit, return a clear `{:reply_error, token, reason}`, reset the run to idle, and pass the error operation through the existing queued-work path. Do not truncate.
- In `supervisor_test.exs`, cover at-limit success, over-limit error with no workers started, empty decomposition, invalid option, and queued work continuing after an over-limit run.
- In the guide, document the default, the `:max_subtasks` option, and the caller-visible over-limit error beside the decomposer example.

No files were edited.
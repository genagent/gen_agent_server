I edited the five test files but could not run `mix test`, `mix format` or `scripts/quality.sh`. Each attempt was blocked pending approval, so none of the changes have been run or mutation-checked.

- `test/gen_agent/lifecycle_hooks_test.exs`:
  - "fires before any prompt dispatches" now has `pre_run` set a marker in state. `pre_turn` reports the marker it sees at dispatch, and the test asserts `true`.
  - ":ok can rewrite the prompt" now uses a Mock function script that sends the prompt it receives. The test asserts `{:backend_prompt, "[prefix] hello"}`.
  - "runs between decision callback and transition" now records `handle_response` and `post_turn` into a trace in state and halts. `post_run` reports the trace, and the test asserts `[:handle_response, :post_turn]`.
- `test/gen_agent/integration_test.exs`: the sleep-based default `handle_event` test now calls `SimpleAgent.handle_event/2` and `handle_error/3` directly. It also checks that both are exported and that both return `{:noreply, ^state}`.
- `test/gen_agent/server_test.exs`: I renamed the TestAgent recovery test and removed the comment that claimed it exercised the `use GenAgent` default.
- `test/gen_agent/event_test.exs`: the timestamp test now asserts the event timestamp lies between `System.monotonic_time(:millisecond)` readings taken before and after construction. The sleep is gone.
- `test/gen_agent_test.exs`: deleted.

I left the checkpointer scenario alone, as the plan said, since it no longer uses Mock scripts. No production, Ensemble or guide files were touched.

To check them, run `mix format`, then `mix test`, then the mutations from the issue.
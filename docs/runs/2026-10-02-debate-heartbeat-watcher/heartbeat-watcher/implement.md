I’ll re-check prompt admission and error handling, then update the two guides and add tests that compile their modules. Supervisor scenario cleanup will stay out of scope.


The claims hold, but the proposed FIFO error handling needs adjustment: a rejected new prompt can fail before older queued prompts run. I’ll keep one Heartbeat batch outstanding and track Watcher’s active event separately so failures stay associated with the right work. Repeated ticks without enough new observations do not queue more prompts.


The guides and tests are written. The ticker monitors and addresses one agent PID, so it cannot send ticks to a replacement registered under the same name. Tests cover failure retention, halted ticks, and overload—including rejection of a new Watcher prompt while an older one is queued.

The test runner hit a sandbox restriction on Mix’s local TCP lock. I’m checking for an offline workaround.


All 53 guide tests pass with the offline Mix lock workaround. The new tests confirm that failures retain the right work, halted Heartbeat ticks queue at most one batch, and ticker shutdown prevents ticks reaching a replacement agent. I’m finishing formatting and lint checks; no core runtime or Supervisor scenario files changed.


- `guides/patterns/heartbeat.md`: Retains failed batches, supervises ticker lifetime, and corrects halt/admission guidance.
- `guides/patterns/watcher.md`: Records originating events and failures; updates overload and API guidance.
- `test/guides/heartbeat_test.exs`: Tests actual guide modules for recovery, halted ticks, overload, and ticker lifecycle.
- `test/guides/watcher_test.exs`: Tests actual guide module for failures, success, and count/byte overload.

Passed: 53 guide tests, 9 final focused tests, formatting, and strict Credo.

Supervisor cleanup acceptance remains scoped to #236 and untouched. No checkout commits or publishing.
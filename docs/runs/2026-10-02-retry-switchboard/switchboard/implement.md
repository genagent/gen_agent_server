I’ll re-check the guide against the runtime, update the facade, and add deterministic tests that execute the guide’s code. I’ll keep changes local to the guide and focused tests, with no network or git mutations.


The findings hold at local HEAD `e9920af`. `notify_ack/2` acknowledges admission even when handling is deferred, so the facade must propagate notification overload errors too. I’ll replace `send/2` with queueing `submit/2`, document the cast behavior of interrupt/resume, and acknowledge only the history cursor captured by the inbox read.


The guide now uses `submit/2` with a single `tell/2` admission call and passes the snapshot cursor in inbox acknowledgments. All seven focused tests pass, including the held-turn ordering test, missing-name behavior, queueing, overloads, and halt/resume. I’m checking formatting, compilation, the full suite, and docs using locally cached dependencies.


- [guides/patterns/switchboard.md](guides/patterns/switchboard.md): Fixed missing-name handling, queueing submission, snapshot acknowledgments, and all identified documentation errors.
- [test/guides/switchboard_test.exs](test/guides/switchboard_test.exs): Added seven deterministic tests compiling and executing the guide’s actual modules.

Validation passed: 267 tests, formatting, compilation with warnings as errors, and docs generation. No core runtime changes, commits, or publishing.
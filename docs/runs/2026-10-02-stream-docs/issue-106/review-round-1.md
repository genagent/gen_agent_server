I’ll read the design inputs and current source, then trace the relay, cleanup paths, and tests without modifying files.


I found a recipient leak when a halt fails queued requests, and the pre-turn test passes atoms to an API that requires strings. The ordering tests also use selective receives, so they would pass even if completion arrived before the events.


REQUEST CHANGES

- **[P2] Leaked recipients on queued halt failure — [lib/gen_agent/server.ex:1676](/private/tmp/gen_agent_issue_106/lib/gen_agent/server.ex:1676).** `fail_halt_aware_queued/1` removes the queued request and sends completion but never deletes its `stream_recipients` entry. That ref will never reach `try_dispatch/4`, so repeated halt/resume cycles accumulate entries indefinitely. Delete the entry when failing the request.

- **[P2] Pre-turn test fails before reaching the callback — [test/gen_agent/stream_to_test.exs:194](/private/tmp/gen_agent_issue_106/test/gen_agent/stream_to_test.exs:194).** The keyword list supplies atoms `:skip` and `:halt`, but `tell_with_completion/5` requires a binary prompt. This raises `FunctionClauseError`. Use string prompts matching the callback clauses.

- **[P2] Ordering assertions do not verify arrival order — [test/gen_agent/stream_to_test.exs:107](/private/tmp/gen_agent_issue_106/test/gen_agent/stream_to_test.exs:107).** Each `assert_receive` selectively searches the mailbox, skipping earlier mismatched events or completion messages. These tests pass even with reversed delivery. Receive any event/completion for the request, then assert its expected shape; apply this to the queued FIFO test too.

- **[P2] Dispatch-failure coverage is missing — [test/gen_agent/stream_to_test.exs:239](/private/tmp/gen_agent_issue_106/test/gen_agent/stream_to_test.exs:239).** Returning a backend error exercises an already-dispatched task, not task-supervisor failure. Add a deterministic unavailable-supervisor case with `stream_to`, asserting one error completion, no events, and recipient cleanup.

The relay approach addresses request correlation and keeps scope focused. Tests were not run; this was a read-only source review.
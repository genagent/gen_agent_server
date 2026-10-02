All four findings are fixed, but I couldn't run `mix format` or `mix test` because the shell blocked them. Nothing has been run against the edits, so please rerun the gates.

Files changed:
- `lib/gen_agent/server.ex`
- `test/gen_agent/stream_to_test.exs`

- **Leaked recipients on queued halt failure:** fixed. `fail_halt_aware_queued/1` now deletes the failed ref from `stream_recipients`.
- **Pre-turn test used atoms:** fixed. The loop now uses the string prompts `"skip"` and `"halt"`, which match the callback clauses.
- **Ordering assertions were selective:** fixed. I added `next_msg/1`, which takes the next `{:gen_agent, _, _, _, _}` message in mailbox order. The ordered tests now use it, so completion arriving before events fails. This covers the basic order, queued FIFO, interrupt follow-up, compact retention and lossless overflow tests. The first three also assert the `:result` event and `refute_received` for stray messages.
- **Missing dispatch-failure coverage:** fixed. The new test "an unavailable task supervisor fails once with no events and no recipient" starts `GenAgent.Server` on a named supervisor, stops that supervisor and calls `tell_with_completion` with `stream_to`. It asserts one `{:error, :task_supervisor_unavailable}` completion, no events, no backend start, a live agent and an empty `stream_recipients`.

The multiline completion assertion near line 316 that failed `mix format --check-formatted` was rewritten, but I couldn't run the formatter on it.
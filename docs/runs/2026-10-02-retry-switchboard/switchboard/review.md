APPROVE

I read the guide, `lib/gen_agent.ex` and `lib/gen_agent/server.ex`, and ran `mix test test/guides/switchboard_test.exs`: 7 passed. I did not run the full suite or docs build.

**Checked against source**
- **Missing names:** `call/1` in `guides/patterns/switchboard.md:277` catches `{:noproc, _}` from the `:gen_statem.call` via the registry (`lib/gen_agent.ex:631,744,778,878`) and maps it to `{:error, :not_found}`. The tests cover `submit`, `poll`, `inbox`, `summary_get`, `summary_update`, `transcript`, `halt` and `stop_session`.
- **`interrupt/1` and `resume/1`:** they are casts that return `:ok` even for a missing name (`lib/gen_agent.ex:793,858`). The guide and test now say this.
- **`send/2` replaced by `submit/2`:** `submit/2` makes a single `GenAgent.tell/2` call with no status preflight, which removes both the full-history copy and the status-then-tell race. `tell` queues when the session is busy or halted. An overloaded queue returns `{:error, {:overloaded, info}}` (`lib/gen_agent/server.ex:921-941`).
- **Tell-path trace test:** it traces `GenAgent` calls during `submit/2` and asserts `tell` is called and `status` and `runtime_snapshot` are not.
- **Inbox ack:** `inbox/2` acknowledges with `{:ack_inbox, seen}` using the snapshot's `length(history)`, and the handler applies `max/2` to the cursor, so a late ack cannot move it backward. `notify_ack/3` is a real call that returns `:ok` or the overload error (`lib/gen_agent.ex:779`, `lib/gen_agent/server.ex:950`). It does not apply the cursor update while a turn is running, but it reports a rejected ack, which the facade passes on.
- **Ordering test:** it holds a turn open, calls `inbox(ack: true)`, then checks `pending_notifications == 1` and `inbox_cursor == 0`. After the turn completes, the in-flight result is still returned as unread.
- **Other doc fixes:** `halt/1` is gone from the public API list and replaced by `notify_ack/2`, `status/1` and the `{:halt, state}` note. `Keyword.drop` is removed, since `:name` and `:backend` are stripped before `init_agent/1` (`lib/gen_agent.ex:531-555`). Broadcast now takes caller-supplied names and keeps each admission result. The `\\n` is fixed.
- **Test method:** the tests compile the guide's real modules from the markdown, which satisfies "compile or execute the guide's actual code".
- **Scope:** only the guide and the new test file changed, and there are no core runtime edits.

**Non-blocking notes**
- `guides/patterns/switchboard.md:~70`: the `SessionAgent` moduledoc says notifications are "used only to update the summary and advance the inbox cursor". It now also carries `halt`. This was already inaccurate.
- The `:not_session` return for another callback's state is a new error atom and the guide documents it, so it is acceptable.
- The `:erlang.trace_pattern` setup in the test is global. It is safe here because the module is `async: false` and cleans up in `on_exit`.
APPROVE

I read the diff against the source and ran the full Ensemble suite. 181 tests passed and `mix format --check-formatted` is clean. I did not run clippy-equivalent checks such as `mix compile --warnings-as-errors`, and Hex resolution is out of scope.

- **Option handling:** `stream_to` is popped from `opts` and validated as nil or a pid in the caller (`server.ex:57-65`). It never reaches `handle_tell`. The test asserts the strategy sees exactly `[observer:, repeat:]`.
- **Dispatch to core:** `dispatch/4` (`server.ex:716-723`) passes `stream_to: self()` only when the token has a recipient. That matches core's `tell_with_completion/5` (`lib/gen_agent.ex:708-716`). Legacy dispatches with a nil token are never streamed.
- **Event forwarding:** the new `handle_info_impl` clause (`server.ex:478-491`) maps the child ref through `in_flight` and `dispatch_contexts`. It emits the session name, token, bare member and per-token ordinal. The early-event claim holds. The ref is registered in the same callback that dispatches, before the mailbox is processed.
- **Ordering and fencing:**
  - Events precede completion because the child's messages arrive in order, and the completion send happens after `finish_token`.
  - `finish_token` (`server.ex:962-966`) clears the recipient. Every terminal path goes through it: `reply_to_token`, cancellation, rejection and agent down. Halt stops the process.
  - A completed child is fenced because its ref leaves `in_flight`.
- **Cancellation:** `drain_child_messages` handles `:event` and `:completion` in arrival order. It is used at the initial drain in `cancel` and again after a negative acknowledgement. Both paths have tests.
- **Scope:** the changes are Ensemble only, plus the Hex constraint `~> 0.7.0` (`mix.exs:46`), which is not weakened. Nothing is committed or pushed.

Minor, non-blocking:
- Two tests read core internals via `:sys.get_state(GenAgent.whereis(...))` and `current_request.stream_to` (`stream_test.exs`, per-token and queued-token tests). They will break if core renames that field.
- In `cancel_token_ref` the post-ack path skips the drain, so events queued before an acknowledged cancel are dropped without being forwarded. That is acceptable for a cancelled token, but the moduledoc does not say it.
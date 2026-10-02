I’ll verify the design against the current source, then add stream forwarding and deterministic tests within Ensemble. I’ll leave package checks to you and won’t run network commands.


The source supports the proposed approach. Early child events can be queued before dispatch returns, but Ensemble registers the child ref before processing its mailbox. I’ll reuse that mapping, add a token recipient map for terminal fencing, and make cancellation drain events and completions in arrival order.


The forwarding code and initial tests are in place. The cancellation race test suspends Ensemble and queues the cancel call before releasing the child, so it exercises the selective drain. Coverage also includes repeated dispatch ordinals, early completion with an active peer, and late-event fencing. I’ll format the edits and run the focused tests; full package checks remain with you.


All 30 focused tests pass. That includes both cancellation drain paths, concurrent tokens with different streaming choices, and cleanup after terminal outcomes. The Hex dependency now requires core `~> 0.7.0`; Hex-resolution CI will need to wait for that release.


- [gen_agent_ensemble.ex](/private/tmp/gen_agent_issue_259_stream/extensions/ensemble/lib/gen_agent_ensemble.ex): Documented opt-in streaming and ordering guarantees.
- [server.ex](/private/tmp/gen_agent_issue_259_stream/extensions/ensemble/lib/gen_agent_ensemble/server.ex): Added token-correlated forwarding, terminal fencing, and ordered cancellation draining.
- [mix.exs](/private/tmp/gen_agent_issue_259_stream/extensions/ensemble/mix.exs): Required core `~> 0.7.0`, retaining local path dependencies.
- [stream_test.exs](/private/tmp/gen_agent_issue_259_stream/extensions/ensemble/test/gen_agent_ensemble/stream_test.exs): Added deterministic streaming, cancellation race, and cleanup tests.
- [streaming_backend.ex](/private/tmp/gen_agent_issue_259_stream/extensions/ensemble/test/support/streaming_backend.ex): Added a gated streaming fixture.
- [format_status_test.exs](/private/tmp/gen_agent_issue_259_stream/extensions/ensemble/test/gen_agent_ensemble/format_status_test.exs): Verified stream-recipient redaction.

Validation: 30 focused tests passed; formatting and diff checks passed. Full package checks remain with you.
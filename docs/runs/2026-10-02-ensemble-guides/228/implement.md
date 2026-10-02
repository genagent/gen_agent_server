I fixed all three findings, but I couldn't run `mix test`, so the new tests have not been run. The command needs approval, which isn't available in this non-interactive session.

Files changed (all uncommitted, in `extensions/ensemble`):
- `guides/workflows/supervisor.md`
- `test/gen_agent_ensemble/workflow_guides_test.exs` (new)
- The four guide edits from the first pass are unchanged.

- **[P2] supervisor.md exception wording:** Fixed. The guide now says the Server's `safely_callback` wrapper (`server.ex:214-222`) catches the raise and logs a sanitized message. It then stops the ensemble with `{:callback_failed, kind, reason_kind}`. It still says the strategy does not issue a `:halt` or an error reply.
- **[P2] supervisor.md anonymous-function prohibition:** Fixed. The "anonymous functions cannot be used" claim is gone. The guide now recommends named function references in `config.exs` and says they hold up better than anonymous functions under release config handling and serialization.
- **[P2] missing executable doc tests:** Fixed. The new `workflow_guides_test.exs` is a separate file and does not touch the draft PR's server, main-module or test files.
  - It reads the Debate and Consensus config blocks with `Config.Reader` and checks that every agent module exists.
  - It checks the Supervisor guide's status examples against `handle_status/1` output for both phase shapes.
  - It asserts the Supervisor and Pipeline claims that were wrong are no longer in the guides.
  - The Supervisor and Pipeline checks are string checks against the guide text; the `{:callback_failed, ...}` and empty-decomposition ones don't exercise runtime behavior. The empty-decomposition behavior is already covered by the existing supervisor test.

The test file is untested, so it may need fixes once someone runs `mix test test/gen_agent_ensemble/workflow_guides_test.exs`.
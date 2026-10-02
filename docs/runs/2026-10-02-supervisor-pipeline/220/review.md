APPROVE

I read the diff and ran it. The change resolves the issue, stays in scope, and every factual claim I checked holds against the code.

**Verification**
- `mix test` in `extensions/ensemble/test/gen_agent_ensemble/strategies` gives 99 passed. The root `mix test` gives 324 passed on three repeat runs.
- One earlier root run showed 323/324 with a single failure. I did not capture which test failed and could not reproduce it. The suite also passes on the stashed baseline. I treat it as flaky, but I did not identify the cause.
- `mix format --check-formatted` is clean in both the root project and the ensemble extension, and the ensemble extension compiles with `--warnings-as-errors`.
- The Mix TCP-lock problem the engineer reported did not occur for me.

**Claims checked**
- **Usage:** Pipeline already aggregated usage, and the change does not redo it. It adds `responses` to the strategy state and puts `metadata.pipeline` on the final response (`pipeline.ex:94-124`). `stages` is ordered, and the final entry is the original response, not the augmented one. That means there is no self-reference loop, and the `:pipeline` key is overwritten only on the returned copy.
- **Retention:** `reset_run` clears `responses` on completion, on error (`pipeline.ex:132`), on active cancel (`pipeline.ex:147`) and on dispatch rejection, which goes through `handle_error`. Every dispatch of a new run starts with `responses: []`, whether immediate or dequeued. Cancelling a queued token leaves the active run's state alone.
- **Repeat reads:** `poll` and `inbox` consume the completed result (`server.ex:~300-325`), and `await` repeats because it reads the stored token. The tests cover this.
- **Scope:** `server.ex` and `gen_agent_ensemble.ex` are untouched, so there is no conflict with draft #342. No backend changes were needed, and the new `metadata` field defaults to `%{}`.
- **Acceptance:** the tests cover multi-stage usage and duration, ordered intermediate outputs, and isolation across runs (queued, errored, cancelled and rejected). They also cover late completions arriving after cancellation, and token reads.
- **Docs:** the docs now point to the callback route for live capture, which matches the issue's correction.

**Non-blocking**
- `lib/gen_agent/response.ex:21`: this adds a public field to the shared `Response` struct. The issue called the shape risky and asked for an explicit comparison of alternatives. That comparison exists only in the chat report, not in the PR body or docs. Put it in the PR description before the PR is marked ready. The `:pipeline` key is reserved by convention only.
- `pipeline_test.exs:5-7`: the alias ordering is slightly off. `mix format` does not flag it, so it is only a style nit.
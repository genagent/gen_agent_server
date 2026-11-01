I’ll check the command APIs and `Structured`’s temporary-file pattern, implement `LastMessage` with fake-executable tests, then run the required checks. I’ll also check whether a native failure run is possible here.

`Structured` provides the ownership pattern, and all four commands expose `output_last_message`. I’ll have `LastMessage.run/3` preserve and read an explicit caller path, creating and removing a temporary file only when no path is set. Non-zero exits will return `{:error, {:process_failed, text, result}}` so callers retain both the file contents and process output.

The implementation and five tests are in place. Mix’s TCP filesystem lock is blocked by the sandbox; `MIX_OS_CONCURRENCY_LOCK=0` allows the checks to run, and the full suite is now running. The native CLI is version 0.165.0; I’ll attempt a bounded failure run with its files kept inside this worktree.

The five new tests pass, as do formatting, compilation and strict Credo. The full suite has 14 failures in existing process-cleanup tests: each fails while calling `ps`, which the sandbox blocks. Dialyzer is still running.

The native CLI attempt could not resolve `api.openai.com` and timed out without creating the output file. I’ll record that result and mark the model-turn failure behavior as unverified.

All seven new tests pass, including option forwarding for observed execution and file-read errors. Dialyzer also passed offline with zero errors. The native probe is recorded in `docs/last-message-native-0.165.0.md`; I’m checking the final full-suite result now.

Implemented `CodexWrapper.LastMessage.run(command, config, opts \\ [])` for Exec, ExecResume, ExecFork and Review. It returns final text with the original result, preserves explicit caller paths, and cleans up owned 0600 temporary files.

Files changed:

- `lib/codex_wrapper/last_message.ex`
- `test/codex_wrapper/last_message_test.exs`
- `test/fixtures/fake_codex_last_message`
- `README.md`, `mix.exs`
- `docs/last-message-native-0.165.0.md`

Seven tests cover all four commands, explicit paths, missing/empty output, non-zero exits, permissions, cleanup after errors/raises, observation options and read errors.

Checks used `MIX_OS_CONCURRENCY_LOCK=0` because the sandbox blocks Mix’s TCP lock:

- `mix format`: passed.
- `mix compile --warnings-as-errors`: passed.
- `mix credo --strict`: passed.
- `mix dialyzer`: passed offline, zero errors.
- `mix test test/codex_wrapper/last_message_test.exs`: 7 passed.
- `mix test`: 602 passed, 14 failed, 4 excluded. All failures are existing process-cleanup tests whose `ps` calls are blocked by the sandbox.
- `git diff --check`: passed.

The native failed-model-turn acceptance check remains unverified. CLI 0.165.0 could not resolve `api.openai.com`; the bounded attempt timed out without creating the output file. The probe is recorded in the documentation.

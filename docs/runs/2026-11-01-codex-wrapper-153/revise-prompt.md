Review of your change, from the operator. The host has network and ran the checks: mix test passes with 616 tests, and compile, format, credo, dialyzer and docs pass. The 14 failures you saw were the sandbox blocking ps, not your change.

The host also ran the native probe you could not. Command, run outside any git repository with codex-cli 0.165.0 on macOS, 2026-11-01:

    codex exec --ephemeral --ignore-user-config --skip-git-repo-check \
      --model codex-wrapper-nonexistent-model -o <dir>/last.txt 'Reply with one word.'

Observed: the CLI started a session, warned that model metadata was not found, printed "ERROR: The 'codex-wrapper-nonexistent-model' model is not supported when using Codex with a ChatGPT account." twice, and exited 1. The -o file was not created.

Make these changes, and nothing else:

1. Rewrite docs/last-message-native-0.165.0.md to record this observed run (command, what was printed in short, exit code 1, no file written) instead of the network-blocked attempt. Keep it short, in the style of docs/compatibility-0.164.0.md.
2. In the LastMessage moduledoc, add one sentence: with codex-cli 0.165.0 a failed turn exits non-zero without writing the file, so an owned file is left empty and the text in {:process_failed, text, result} is "".
3. Run mix format and mix test test/codex_wrapper/last_message_test.exs (with MIX_OS_CONCURRENCY_LOCK=0 if needed) and report the results.

I’ll update the probe record and moduledoc with the host’s observed result, then run the two requested checks.

Updated only the native probe document and `LastMessage` moduledoc to record the observed exit 1, no file written, and empty returned text for an owned file.

Checks:

- `MIX_OS_CONCURRENCY_LOCK=0 mix format`: passed.
- `MIX_OS_CONCURRENCY_LOCK=0 mix test test/codex_wrapper/last_message_test.exs`: 7 tests passed.

I’ll keep this to a read-only check of the wrapper’s current source, tests, and docs.


At `0f09d8f`, the undefined `--verbose` defect remains unresolved. No files changed; tests and CLI commands were not run.

Claims that still hold:

- `Config.new/1` accepts `verbose: true`, and `base_args/1` emits `["--verbose"]`: [config.ex:42](/private/tmp/codex_wrapper_fix_123_20261002/lib/codex_wrapper/config.ex:42), [config.ex:71](/private/tmp/codex_wrapper_fix_123_20261002/lib/codex_wrapper/config.ex:71).
- Both fresh and resume streams prepend it: [exec.ex:326](/private/tmp/codex_wrapper_fix_123_20261002/lib/codex_wrapper/exec.ex:326), [exec_resume.ex:255](/private/tmp/codex_wrapper_fix_123_20261002/lib/codex_wrapper/exec_resume.ex:255). Synchronous commands also prepend it through [command.ex:25](/private/tmp/codex_wrapper_fix_123_20261002/lib/codex_wrapper/command.ex:25).
- Tests explicitly endorse the broken behavior: [config_test.exs:17](/private/tmp/codex_wrapper_fix_123_20261002/test/codex_wrapper/config_test.exs:17) accepts true; [config_test.exs:66](/private/tmp/codex_wrapper_fix_123_20261002/test/codex_wrapper/config_test.exs:66) expects the flag.
- README and API docs still advertise support: [README.md:630](/private/tmp/codex_wrapper_fix_123_20261002/README.md:630), [config.ex:39](/private/tmp/codex_wrapper_fix_123_20261002/lib/codex_wrapper/config.ex:39), [codex_wrapper.ex:94](/private/tmp/codex_wrapper_fix_123_20261002/lib/codex_wrapper.ex:94) and `:173`, plus [iex.ex:48](/private/tmp/codex_wrapper_fix_123_20261002/lib/codex_wrapper/iex.ex:48).
- Contract checking still excludes `Config.base_args/1`: [codex.contract.ex:44](/private/tmp/codex_wrapper_fix_123_20261002/lib/mix/tasks/codex.contract.ex:44).
- Streaming still separates stderr and discards exit status: [config.ex:95](/private/tmp/codex_wrapper_fix_123_20261002/lib/codex_wrapper/config.ex:95), [runner/port.ex:69](/private/tmp/codex_wrapper_fix_123_20261002/lib/codex_wrapper/runner/port.ex:69).

No scoped defect is already fixed. Two qualifications: `:no_terminal_event` is an adapter outcome, not an error defined here; the reported `$2` fixture belongs elsewhere—the current [fake_codex.sh:6](/private/tmp/codex_wrapper_fix_123_20261002/test/fixtures/fake_codex.sh:6) scans arguments for `--version`.

Smallest concrete change:

1. **`lib/codex_wrapper/config.ex`** — Keep the struct field and public signatures. Reject `verbose: true` in `new/1` with `ArgumentError`: “verbose: true is unsupported: the Codex CLI does not define --verbose”. Apply the same guard in `base_args/1` for directly constructed or updated structs; return `[]` for default/false.
2. **`test/codex_wrapper/config_test.exs`** — Replace positive verbose tests with rejection tests, including direct structs. Preserve explicit-false compatibility coverage.
3. **`test/codex_wrapper/stream_routing_test.exs` and `command_test.exs`** — Verify fresh/resume streams and synchronous commands reject true before invoking a recording runner; default/false argv contains no `--verbose`.
4. **README and the three API documentation files above** — Replace advertised support with “Compatibility option: only `false` is supported; `true` raises before CLI execution.”

Keep `:verbose` in option-routing lists so convenience APIs reach validation instead of silently ignoring it. No runner, contract-task, unrelated-flag, or ephemeral changes are needed for this fix.
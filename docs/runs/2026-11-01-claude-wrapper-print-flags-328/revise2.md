The contract task now skips the five flags on CLI versions older than 2.1.309. Nothing has been run. Please run the checks, then `mix claude.contract` against 2.1.220 and 2.1.316.

**Flags tagged:** only the five from the CI report, each at `"2.1.309"`. I added no others. This PR's specimens emit eleven new flags, and the six not reported must already be accepted by 2.1.220:
- `--allow-dangerously-skip-permissions`, `--chrome`, `--no-chrome` and `--forward-subagent-text` have no fallback probe, so they must be in its help.
- `--append-subagent-system-prompt` and `--advisor` are hidden flags, so they must have passed the missing-operand probe. An unknown flag would have failed it.

This depends on the error list you pasted being complete; I couldn't see the CI log. Flags that existed before this PR are untagged.

**`lib/mix/tasks/claude.contract.ex`**
- `@checked_from` maps each flag to the first version it is checked on. Its comment says this is the pinned CI version where the flag was seen, not a bisected introduction version.
- `reported_version/1` reads the first `x.y.z` from the `--version` output (`"2.1.220 (Claude Code)"` gives `"2.1.220"`). `run/1` passes it to `check/3`.
- On an older version, a tagged flag is dropped before the help lookup, so it gets neither a "not documented" finding nor a hidden-flag probe. Untagged flags are checked as before.
- `check/1` and `check/2` still work. With no version, every flag is checked, which keeps the existing tests and covers `--version` output with no version number in it.
- `checked_from/0` and `reported_version/1` are exposed with `@doc false` for the tests.

**`test/mix/tasks/claude_contract_test.exs`**, using the existing fake executables:
- On 2.1.220, `--restricted` missing from help is not a finding. On 2.1.309 and 2.1.316 it is.
- On 2.1.220, the untagged `--removed-option` is still a finding.
- `--append-subagent-system-prompt-file`, using the fake that rejects it as unknown: no finding on 2.1.220 because it isn't probed, and a finding on 2.1.309.
- With no version, a tagged flag is still checked.
- The five tags are each `"2.1.309"`, and `reported_version/1` parses the version and returns `nil` when there is none.

**`README.md`:** the "Native CLI compatibility" section now says flags newer than a pinned version are checked from the version they are tagged with.

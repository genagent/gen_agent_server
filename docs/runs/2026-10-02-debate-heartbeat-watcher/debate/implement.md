I couldn't run the tests or the format check. Both `mix` commands were blocked for approval in this session, so neither edit has been run.

Files changed: `guides/patterns/debate.md`, `test/guides/debate_test.exs`.

- **[P2] Completion example consumed one report and ignored the sender:** Fixed, but unverified. The guide's usage block now loops over `[handle.a, handle.b]`. For each name it does a `receive` that pins the sender (`{:debate, ^name, :finished}` or `{:debate, ^name, {:failed, reason}}`). This collects both reports and cannot take a leftover report from an earlier debate.
- **Repeated-debate regression test:** Added in `test/guides/debate_test.exs`. It runs a 2-round debate and then a 3-round debate in the same process. Both use an `await_reports/1` helper that mirrors the guide's loop. It asserts that the second debate's agents have completed 3 rounds, that the transcript order is correct, and that no stray reports remain.

Please run `mix test test/guides/debate_test.exs` and `mix format --check-formatted`.
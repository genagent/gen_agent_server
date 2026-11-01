I changed the one `Version.` call I had added. In `checked_on?/2` in `lib/mix/tasks/claude.contract.ex`, it now reads `Elixir.Version.compare(version, from) != :lt`, so it calls Elixir's `Version` rather than the aliased `ClaudeWrapper.Commands.Version`. Nothing else changed. `reported_version/1` uses only `Regex.run/3`, so it didn't need the change.

I haven't run anything. To confirm, please run `mix compile --warnings-as-errors`, then `mix test test/mix/tasks/claude_contract_test.exs`, and then the full checks.

I made the changes, but I could not run `mix test`, `mix format`, or the linter. The sandbox denied them, so none of this is verified.

- **Not checked:** Whether the invalid-option cases return `{:error, %ArgumentError{}}` is an assumption taken from the issue's report for capture limits. The `Process.sleep(200)` in the retention test is timing-based.
- **Next step:** Run `mix format`, `mix test` and `mix credo`/the Elixir equivalent before pushing.

Files changed:

- `lib/gen_agent/server.ex`
  - Added `validate_watchdog!/1`, which accepts a positive integer or `:infinity` and otherwise raises `ArgumentError`.
  - `init` now validates `:watchdog_ms`, and validates `:max_tell_results` as a non-negative integer with the existing pending-limit check.
  - Both errors take the same startup path as the capture limits.
- `lib/gen_agent.ex`
  - The `start_agent/2` docs now cover both options: defaults, units, `:infinity`, and zero retaining nothing.
  - They list every reserved key.
  - They state that invalid values return `{:error, %ArgumentError{}}` and that missing `:name` or `:backend` raises `KeyError`.
  - They state that `:task_supervisor` is forwarded to `init_agent/1` and that `child_spec/2` is how to pick a task supervisor.
  - They note that an explicit `nil` uses the default.
- `README.md`: the watchdog bullet now names `:watchdog_ms` with units and default, and documents `:max_tell_results`.
- `test/gen_agent/integration_test.exs`
  - Invalid `:watchdog_ms` (`-5`, `0`, `"600000"`, `:never`, `1.5`) returns an `ArgumentError`.
  - Invalid `:max_tell_results` (`-1`, `"100"`, `:infinity`, `:unlimited`, `1.5`) returns an `ArgumentError`.
  - Boundary values are accepted: watchdog `1` and `:infinity`.
  - Cache `0` retains nothing, and cache `1` keeps only the newest result.
  - `start_agent/2` forwards `:task_supervisor` and other unreserved options to `init_agent/1` and strips the reserved keys.

I kept the existing `KeyError` for missing `:name` or `:backend`, since an existing test requires it. I also kept the `:task_supervisor` forwarding behavior and documented it rather than changing it.
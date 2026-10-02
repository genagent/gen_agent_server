APPROVE

The change is correct and in scope. I read the files and did not run the tests, as the task said the caller would run the package checks.

**Claims checked against the code**
- `GenAgentEnsemble.Backends.Echo` exists in `lib/gen_agent_ensemble/backends/echo.ex`. Its own moduledoc uses the same `{"w", GenAgentEnsemble.Agents.Simple, backend: ...Echo}` pattern as the new example.
- `GenAgentEnsemble.Agents.Simple` exists in `lib/gen_agent_ensemble/agents/simple.ex`.
- `Strategies.Solo` takes `agent: {name, module, opts}` (`solo.ex:27`), which matches the new moduledoc shape.
- `lib/gen_agent_ensemble.ex:12-19`: the example now uses shipped modules only. Replacing the undefined `MyAgent` with `Simple` goes slightly past the issue's wording, but it is the same problem, since a copied example would otherwise still fail.
- `config/runtime.exs:17`: the comment now names Echo.
- A grep of `lib`, `guides`, `config`, `README.md` and `mix.exs` for `mock`, `MyAgent` and `scripted` (case-insensitive) finds nothing. The packaged files are `lib guides config mix.exs README.md CHANGELOG.md` (`mix.exs:87`), so no shipped reference to the test-only Mock remains.
- The test-only Mock modules are untouched. The diff is three files, with no new backend behavior.

**Minor, not blocking**
- `shipped_backend_references_test.exs:8-19`: the first test greps source text, so it checks the wording and not that the example works. The second test checks that both modules load. Both are cheap and fit "tests cover each case". The relative paths work because `mix test` runs from the package directory.
- The new test file is staged (`A`) while the two edits are unstaged. The task said not to commit, so this is harmless, but the caller should know.
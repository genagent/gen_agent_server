REQUEST CHANGES

The dependency change and doc edits are correct, but the issue's acceptance criterion ("Tests cover each case above") isn't met.

**What checks out**
- `mix.exs:37`: `"~> 0.3.5 or ~> 0.4.0"` is valid Mix requirement syntax. It keeps the 0.3.5 line and accepts 0.4.0, which is what claude_wrapper 0.14.5 declares, so the two ranges now overlap.
- I unpacked `forcola-0.3.5.tar` and `forcola-0.4.0.tar` from the local Hex cache. `lib/forcola.ex`, `lib/forcola/result.ex` and `lib/forcola/stream.ex` are byte-identical between them. The 0.4.0 changelog lists only `Forcola.Duplex` additions.
- The runner's calls (`Forcola.run/2`, `Forcola.Stream.lines/2`, `Forcola.Result`, `Forcola.Stream.Error`, and the `:timeout_ms`, `:merge_stderr`, `:cd` and `:env` options) are unchanged in 0.4.0. `run_error` is still `{:timeout, Result.t()} | {:spawn, term()}`, which matches the clauses at `lib/codex_wrapper/runner/forcola.ex:62-76`.
- The stdin-fix comment (`lib/codex_wrapper/runner/forcola.ex:18-19`) is accurate: 0.3.4 added the fix, and both 0.3.5 and 0.4.0 are later.
- The README (`README.md:654`) and `runner.ex:17` examples match `mix.exs`.
- No package version or release files were touched, and nothing was edited outside this repo.

**Findings**
1. No test was added, though the issue's Acceptance section requires tests for each case. The diff touches no `test/` files. At minimum, a test should assert the declared requirement accepts both 0.3.5 and 0.4.0 and rejects other versions. One option is `Version.match?/2` against the `:forcola` entry in `CodexWrapperEx.MixProject.project()[:deps]`.
2. `mix.lock:9` still pins forcola 0.3.5, so the existing `:forcola` runner tests in `test/codex_wrapper/runner/forcola_test.exs` only exercise 0.3.5. My source diff shows the runner's calls behave the same on 0.4.0, but nothing in the repo exercises it. Either add a CI job or documented step that runs those tests with 0.4.0, or at least say in the PR that this was only verified by source comparison.
3. The implementer ran no tests (`git diff --check` only). The project's `cargo`-style gates for Elixir (`mix format --check-formatted`, `mix test`, credo) weren't run either. The change is small, but the report shouldn't be taken as validation.
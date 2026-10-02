I’ll check the dependency declarations, lockfiles, Forcola runner calls, and relevant docs/comments in this checkout, then report the remaining mismatch and minimal edit plan.

## Claims that still hold

- The package still restricts Forcola to `~> 0.3.5` in [mix.exs](/private/tmp/codex_wrapper_forcola_196/mix.exs:37). That excludes `forcola 0.4.0` and conflicts with Claude’s stated `~> 0.4.0` requirement.
- The lockfile pins Forcola to `0.3.5` in [mix.lock](/private/tmp/codex_wrapper_forcola_196/mix.lock:9).
- The dependency instructions repeat the old constraint in [README.md](/private/tmp/codex_wrapper_forcola_196/README.md:654) and [lib/codex_wrapper/runner.ex](/private/tmp/codex_wrapper_forcola_196/lib/codex_wrapper/runner.ex:17).
- The runner’s compatibility comments also name the old floor in [lib/codex_wrapper/runner/forcola.ex](/private/tmp/codex_wrapper_forcola_196/lib/codex_wrapper/runner/forcola.ex:18).

## Already resolved or verified

- The stale Claude downgrade workaround does not apply to this repository: this checkout is the Codex wrapper, and the Claude integration is outside the requested scope.
- The runner already calls `Forcola.run/2` and `Forcola.Stream.lines/2`, passing the documented options and handling `Forcola.Result` and `Forcola.Stream.Error`. Forcola’s published API documentation confirms those entry points and result/error behavior; however, this checkout’s lock pins 0.3.5, so the checked-in tests do not themselves establish runtime compatibility with 0.4.0. The caller plans to verify resolution and run the suite.

## Smallest change plan

1. In `mix.exs`, widen the optional dependency to `~> 0.3.5 or ~> 0.4.0`, preserving the 0.3 line while allowing 0.4.
2. Update `README.md` and `lib/codex_wrapper/runner.ex` dependency examples to show both supported lines.
3. Update the Forcola floor wording in `lib/codex_wrapper/runner/forcola.ex` to describe the stdin fix without implying that only `~> 0.3.5` is supported. Review the runner’s calls and result/error handling against Forcola 0.4.0 while making that comment update.

No files were changed.
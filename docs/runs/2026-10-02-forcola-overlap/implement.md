I’ll verify the current declarations and runner API references, then make only the dependency and documentation/comment edits in scope.

The declarations now allow both Forcola lines while preserving 0.3.5 support. I’ve updated the example constraints and the stdin compatibility comment; I’m checking the final diff and scope now.

Changed four files:

- [mix.exs](/private/tmp/codex_wrapper_forcola_196/mix.exs): allow optional Forcola `~> 0.3.5 or ~> 0.4.0`.
- [README.md](/private/tmp/codex_wrapper_forcola_196/README.md): update the dependency example for both supported lines.
- [lib/codex_wrapper/runner.ex](/private/tmp/codex_wrapper_forcola_196/lib/codex_wrapper/runner.ex): update the runner dependency example.
- [lib/codex_wrapper/runner/forcola.ex](/private/tmp/codex_wrapper_forcola_196/lib/codex_wrapper/runner/forcola.ex): clarify that both supported lines include the stdin fix.

The runner’s existing calls use `Forcola.run/2`, `Forcola.Stream.lines/2`, `Forcola.Result`, and `Forcola.Stream.Error`. `git diff --check` passed. I did not run tests or network commands.
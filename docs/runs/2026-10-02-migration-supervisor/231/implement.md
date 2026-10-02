I changed `MIGRATION.md` and added `test/migration_dependency_test.exs`, but I could not run the new test or `mix format`. The sandbox denied both commands, so the test is unverified.

- **MIGRATION.md sparse explanation (reviewer finding 1): fixed.** The prose now says the core project files are absent and that `../..` is the checkout root with no core `mix.exs`. It also says `mix deps.get` succeeds while `mix compile` fails, and it keeps the `GEN_AGENT_HEX=1` requirement.
- **Missing behavioral coverage (reviewer finding 2): fixed, not run.** The new test builds a local `file://` Git fixture shaped like the monorepo, with core at the root and a sibling package under `integrations/claude`. It consumes that fixture from throwaway Mix projects and covers four cases:
  - `subdir` without `GEN_AGENT_HEX` compiles against the source core.
  - `sparse` with `GEN_AGENT_HEX=1` compiles against the stand-in published core.
  - `sparse` without the variable passes `deps.get` and fails `compile`.
  - A local `path:` dependency compiles against the source core.

The fixture needs no network. Its `GEN_AGENT_HEX=1` branch points at a local stand-in core instead of Hex, which is the limitation the issue allowed. The test file says so in a comment, and the real published package still needs the caller's re-run.
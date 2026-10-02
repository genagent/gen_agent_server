APPROVE

I read the guide, the test, and `lib/gen_agent/server.ex`. I did not run `mix test`, because plan mode forbids it, so the tests have not been run. `mix format --check-formatted` on the test file passes.

**What I checked and found correct**
- **Git failures:** `post_turn/3` (guide ~176–196) now turns a failed add, commit or rev-parse into `{:failed, reason}` and logs it. `pre_turn/2` (guide ~143–153) halts on that phase.
- **Log failure:** The final `git log` runs in `pre_turn/2`, before `:finished` is set. That is needed because `post_run/1` cannot change state.
- **Core behavior:** The halt path behaves as the guide describes. A `{:halt, _}` from `pre_turn/2` calls `transition_to_halted`, which calls `post_run` with the new state (`server.ex:1122–1127`, `1658–1666`). No core files changed.
- **Workspace allocation:** The default ID is 16 random bytes. A caller-supplied ID must match `\A[a-z0-9][a-z0-9-]{0,62}\z`. `File.mkdir/1` is exclusive, so an existing repository is never reused. `init_agent/1` rejects bad IDs before any filesystem access.
- **Git environment:** Signing, hooks, system and global config, and templates are all neutralized. `GIT_CONFIG_GLOBAL` does need Git 2.32+, as the guide says. Each command runs under a `Task` with a timeout.
- **Cleanup on failed setup:** `pre_run/1` removes the partial directory when setup fails.
- **cwd timing:** `cwd` is computed in `init_agent/1` and passed to the backend before `pre_run/1` runs (`server.ex:147–148`).
- **Startup error:** An error from `init_agent/1` surfaces as `{:backend_start_failed, reason}` (`server.ex:168`).
- **`terminate_agent/2`:** It is not called on failed initialization, matching `server.ex:168` and `194–204`.
- **Variation claims:** The Checkpointer variation now says to return `{:noreply, state}` with `phase: :awaiting_review`. The reference to a nonexistent helper module is gone. No variation claims `terminate_agent/2` runs no matter what.
- **Scope and style:** Only the guide and one test file changed, with no em dashes. The test compiles the guide's own code block rather than a copy. It covers each issue case: injected add/commit/rev-parse/log failures, traversal-like IDs, restart collision via real `elixir` subprocesses, cleanup on setup failure, a Git timeout, and hostile global config.

**Findings, all minor**
1. `guides/patterns/workspace.md:40-41` is stale. The `post_run/1` bullet says it "prints the branch, commit log, and workspace path when the agent halts cleanly." It now fires on a halt with a failed phase and prints the log only for `:finished`. The new prose at ~337–340 is right, so the two now disagree. Fix the bullet to match.
2. `guides/patterns/workspace.md:328` says "post_run (only on clean halt)". That is ambiguous next to line 339, which says it fires on a failed-phase halt. Say "on halt".
3. `test/guides/workspace_test.exs`, last test: the variation and cleanup claims are checked only by substring match on the guide text. That is weak, but acceptable because the lifecycle claims are exercised elsewhere.
4. `git/3` in the guide does not clear inherited `GIT_DIR`, `GIT_WORK_TREE` or `GIT_AUTHOR_*` variables. This is a small gap in the "deterministic Git" goal. It is not required by the issue, so I would only add a note.
5. The restart test depends on `elixir` being on `PATH` and on `-pa` pointing at the compiled GenAgent. That is plausible but is the most likely thing to break in CI, so confirm it with a real `mix test` before merge.
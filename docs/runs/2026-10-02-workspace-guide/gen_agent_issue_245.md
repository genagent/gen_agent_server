Found by the 2026-10-01 review at `b8f8ab4` and re-verified against `main` at `1a03608` by a read-only Codex worker in a `gen_agent_server` verification pool (genagent/gen_agent_server#25). One verifier per finding: treat file and line references as the starting point for the fix, and re-check them.

## Problem

### Workspace guide post_turn/3 silently discards git failures

When git add, git commit or git rev-parse fails, post_turn/3 returns {:ok, state} with no log and no state change. The agent continues self-chaining and halts as :finished with files written but not committed. post_run/1 also ignores the exit status of git log.

**Verification on current main.** `post_turn/3` writes the file, then returns `{:ok, state}` without logging if `git add`, `commit`, or `rev-parse` returns a nonzero status; it leaves the commit list unchanged (guides/patterns/workspace.md:155–169). The runtime applies the already chosen self-chain or halt transition after `post_turn` (lib/gen_agent/server.ex:1255–1293), and the guide marks the final turn `:finished` (guides/patterns/workspace.md:193–197). `post_run/1` discards the `git log` exit status (guides/patterns/workspace.md:176–183). A `rev-parse` failure can occur *after* a successful commit, so the file is not necessarily uncommitted.

### Workspace guide derives a persistent directory from System.unique_integer and reuses old repositories

The usage passes `session_id: System.unique_integer([:positive])` and pre_run/1 uses it for a directory under the OS temp dir with File.mkdir_p!/1. unique_integer values are unique only within one VM and restart in the same narrow range, so a later run can land in a previous run's repository. git init on an existing repository succeeds, so the new run commits on top of the old history and old paragraph files stay in the tree.

**Verification on current main.** The usage supplies `System.unique_integer([:positive])` as the session ID (`guides/patterns/workspace.md:221`). `pre_run/1` builds a temp path from that ID, creates it with `File.mkdir_p!/1`, and runs `git init` without checking whether a repository is already there (`guides/patterns/workspace.md:95`). A reused ID can therefore reuse an old repository and its history. `post_turn/3` writes numbered paragraph files without removing existing files; old files with numbers beyond the new run’s turns remain (`guides/patterns/workspace.md:148`).

### Workspace guide uses session_id in a filesystem path without validation

session_id is interpolated into the workspace path and created with File.mkdir_p!/1 before any check. A value containing `..` segments resolves outside the workspace base and git init creates a repository there before failing on the branch name. In the guide the value comes from the developer; in an application that takes session ids from a request it is caller-controlled.

**Verification on current main.** `session_id` is taken from options without validation (guides/patterns/workspace.md:76-80). `pre_run/1` interpolates it into a path, creates that directory, then runs `git init` with the same value in the branch name (guides/patterns/workspace.md:95-103). For example, `/../../outside` resolves beyond the workspace base despite the `session-` prefix. Git creates `.git` before `https://code.googlesource.com/git/+/cbc882ea388143bd6bbed139f97f67589777be60/builtin/init-db.c#427`. The guide supplies a generated integer (guides/patterns/workspace.md:216-221); request control would arise in an application that passes request data as `session_id`.

### Workspace guide git helper depends on the user's global git configuration and leaves directories behind on failure

The helper runs git with the caller's environment. Global settings such as commit.gpgsign, core.hooksPath or init.templateDir apply inside the agent workspace, and there is no timeout on System.cmd/3. When pre_run/1 fails the created directory and `.git` remain. The guide does not show what a caller sees when pre_run/1 fails.

**Verification on current main.** I’m checking the helper and its failure path against the claim.

VERDICT: CONFIRMED

The helper calls `System.cmd/3` with only `cd` and `stderr_to_stdout`, so it inherits the caller’s Git configuration and sets no timeout (`guides/patterns/workspace.md:207–209`). `pre_run/1` creates the directory before running Git; if a later command fails, it returns an error without removing the directory or initialized `.git` (`guides/patterns/workspace.md:95–110`). The guide’s usage shows only success (`guides/patterns/workspace.md:213–239`). Since `pre_run/1` runs after `start_agent/2` returns, its error instead stops the agent with `{:pre_run_failed, reason}` (`lib/gen_agent.ex:291–303`; `lib/gen_agent/server.ex:215–224`).

### Workspace guide tool-use variation cannot pass the pre_run-created workspace as backend cwd

The variation says to swap the backend to gen_agent_claude with `cwd: state.workspace`. Backend options are returned from init_agent/1 and the backend session is started before pre_run/1 runs, and no hook can change the session afterwards, so state.workspace is nil at the only point where cwd can be set. The README and the pre_run/1 callback doc both name worktree creation as the purpose of pre_run/1 and point to this guide.

**Verification on current main.** The guide sets `state.workspace` only in `pre_run/1`, but proposes `cwd: state.workspace` for the Claude backend (guides/patterns/workspace.md:95–107, 275–279). The server passes options from `init_agent/1` to `backend.start_session/1` before running `pre_run/1` (lib/gen_agent/server.ex:147–167, 215–218). Claude stores `cwd` in that session’s options for later prompts (integrations/claude/lib/gen_agent/backends/claude.ex:61–84, 110–116). As written, the variation cannot obtain the newly set workspace path. A path computed in `init_agent/1` and created in `pre_run/1` would work. The README and callback docs do recommend worktree creation in `pre_run/1` (README.md:189; lib/gen_agent.ex:292–299).

### Workspace guide variations contradict the Checkpointer guide and reference a module that does not exist

Three statements in the Variations and ordering sections are inaccurate: pairing with Checkpointer by halting in :awaiting_review (the Checkpointer guide's central rule is not to halt), a 'Workspace helper module' with create_worktree/3 and remove_worktree/2 that is not in the repository, and terminate_agent/2 described as running on any termination 'no matter what happens'.

**Verification on current main.** The Workspace variation says to halt in `:awaiting_review` (`guides/patterns/workspace.md:280`); Checkpointer explicitly keeps that phase idle because halting blocks review prompts (`guides/patterns/checkpointer.md:17`). Workspace references a helper “once extracted” with `create_worktree/3` and `remove_worktree/2`, but neither function is defined in the repository (`guides/patterns/workspace.md:268`). Its “any termination” cleanup promise is also too broad: failed initialization reaches a `terminate/3` clause that does not call `terminate_agent/2` (`lib/gen_agent/server.ex:168`, `lib/gen_agent/server.ex:185`).

## Acceptance

- Tests cover each case above.

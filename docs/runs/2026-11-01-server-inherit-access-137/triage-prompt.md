You are triaging one GitHub issue in gen_agent_server, an Elixir OTP application that runs Claude and Codex CLI sessions. The current directory is a git worktree of the repository on branch feat/inherit-access-137, with dependencies compiled. You can read files and run read-only commands. Do not edit files.

Your output is used by an operator and by a separate implementation agent. Produce exactly two sections, with these headings and nothing before the first one:

## PLAN

A pull request plan for this issue, as Markdown bullets: what changes in which files, which acceptance items each change covers, decisions the issue leaves open and how you resolved them, and anything out of scope. Factual, no marketing tone, no em dashes.

## PROMPT

The full prompt for the implementation agent. It must be self-contained (the agent will not see this triage), and must include:
- what to implement, file by file, with the existing functions, patterns and current line numbers it should follow;
- the acceptance list from the issue, corrected where your checks disagree with it;
- the constraints: work only in the current directory; no git commands that change history, branches or remotes; follow existing conventions; run mix format, mix compile --warnings-as-errors, mix test in the root and mix test in every project under extensions/ before finishing; finish with a summary of files changed, API added, tests added, the exact check commands run with results, and anything not done with the reason;
- the sandbox notes: the implementation agent runs in a Codex workspace_write sandbox with no network; it must run Mix with MIX_OS_CONCURRENCY_LOCK=0; tests that inspect OS processes or open sockets fail there and the host run is authoritative

Before writing, check the issue's claims and line references against the current code, and say in PLAN where they differ.

The issue follows.

# feat!: inherit the creator's tools and permissions by default

## Problem

A session run headless in the server cannot do what the same CLI does when run by the same user in a terminal, because the server overrides the CLI's own configuration on every route:

| Provider | Server defaults today (`lib/gen_agent_server/providers.ex`) | Effect |
| --- | --- | --- |
| Codex | `sandbox: :read_only` (or `:workspace_write`), `approval_policy: :never`, `ignore_user_config: true` | No network, no writes outside the cwd; the user's `~/.codex/config.toml` (model, sandbox, MCP servers) is ignored |
| Claude, dynamic routes | `permission_mode: :dont_ask`, `tools: ["Read", "Grep", "Glob"]` | Cannot run commands |
| Claude, profiles | `permission_mode: :plan` | Cannot edit or run commands |
| Claude, `accept_edits` | `permission_mode: :accept_edits` | Edits files; Bash is denied without a prompt |
| Startup agents (`RuntimeConfig`) | Claude `:plan`; Codex read-only, user config ignored | As above |

In the procedure runs (#134), this is why the operator prepares worktrees and dependencies, pushes and opens pull requests: the agent cannot reach the network or GitHub. In run 3, a Claude `accept_edits` route wrote an 848-line change without running a single check ("All checks: blocked by Bash approval").

Native subagents (Claude Code's `Agent` tool, Codex's `collaboration.spawn_agent`) have no permission or sandbox parameter: a subagent inherits its creator's tools and permissions. Server sessions should behave the same way by default.

## Change

- Add an `inherit` access value, and make it the default for dynamic routes, profiles and startup agents:
  - Codex `codex_sandbox: inherit` passes no `--sandbox`, and `codex_user_config` defaults to `inherit`, so the user's config decides. `approval_policy: :never` stays, because a headless session cannot answer an approval prompt.
  - Claude `claude_permission_mode: inherit` passes no `--permission-mode` and no `--tools`, so the user's settings decide.
- Add an explicit Claude mode for the caller's permission mode as the CLI accepts it (`auto`, `bypass_permissions`, `dont_ask`), so a caller running in one of those modes can give a headless session the same one. This matters because a user's interactive permission mode may come from the client app rather than `~/.claude/settings.json`.
- Keep every existing narrowing value (`read_only`, `workspace_write`, `plan`, `accept_edits`) as an explicit choice.
- `describe_instance` reports the resolved access per route, including `inherit`.
- README and moduledocs: document inheritance as the default, and what a headless session cannot do (answer prompts).

This changes defaults, so it is a breaking change (`feat!:`).

## Acceptance

- [ ] A route with no access option builds backend options with no sandbox, permission-mode or tools override, and Codex user config inherited.
- [ ] Each narrowing value builds the same options as today.
- [ ] The new Claude modes build the matching `--permission-mode`.
- [ ] Profiles, dynamic routes and startup agents share the default; their tests are updated.
- [ ] `describe_instance` and the operation schemas list the new values.
- [ ] Format, warnings-as-errors compile, tests and the extension matrix pass.


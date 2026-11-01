You are reviewing a change to gen_agent_server, an Elixir OTP application that runs Claude and Codex CLI sessions before it is committed. The current directory is the worktree with the change applied. You can read any file. You cannot run commands; the operator runs the checks.

Review the change against the issue below. Report:
1. For each acceptance item: met, not met, or not verifiable by reading, with the file and line that shows it.
2. Defects: incorrect behaviour, races, missing cases, inconsistencies with the surrounding code's conventions, doc claims the code does not support. For each, file:line, what is wrong, and a concrete fix.
3. Anything in the diff that the issue did not ask for, and whether it should stay.
4. A verdict on the last line: APPROVE or REQUEST CHANGES.

Report only what you can point to in the code. Before calling code dead or unused, search the whole repository, including extensions and tests. Do not restate the change.

# Issue: feat!: inherit the creator's tools and permissions by default

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


# Diff

The diff of the implementation turn followed here.

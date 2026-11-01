# Agent interface

Status: proposed, refined by each procedure run
([working-an-issue.md](https://github.com/genagent/gen_agent_server/pull/134)). Updated after every run that
uses or changes it.

One call that starts or continues an agent session, shaped like the subagent
tools Claude Code and Codex already give their sessions, over the server's
existing operations. A Claude or Codex session that has the server's MCP
plugin can use it as a subagent that keeps its session across calls and
conversations.

## What the native tools do

| | Claude Code `Agent` | Codex `collaboration.*` |
| --- | --- | --- |
| Task text | `prompt` | `message` |
| Label | `description` | `task_name` (also its address) |
| Kind | `subagent_type`: a named agent definition | none |
| Model, effort | `model`, `effort` | `model`, `reasoning_effort` |
| Context | the `fork` type inherits the conversation | `fork_turns: all \| none` |
| Where | `isolation: worktree \| remote` | shared cwd |
| Continue | `SendMessage(to, message)` | `followup_task(target, message)` |
| Result | pushed to the parent on completion | pushed to the parent; `wait_agent(timeout_ms)` |
| Other | `TaskStop` | `list_agents`, `interrupt_agent`, `send_message` |
| Access | inherited; no parameter | inherited; no parameter |
| Turn limit | none | none |

Neither tool has a permission, sandbox or tool parameter: a subagent gets its
creator's access. Narrowing is a property of a named agent definition, not of
a call.

## What the server has today

Four base operations, each available through `mix gen_agent_server.ops`,
release RPC and the MCP extension:

| Operation | Parameters | Returns |
| --- | --- | --- |
| `create_instance` | `instance`; `config`: `cwd`, `max_in_flight`, `max_results`, `routes[]` of `name`, `provider`, `model`, `effort`, `cwd`, `claude_permission_mode` or `codex_sandbox`, `codex_user_config`, `codex_response_text` | the resolved routes |
| `invoke` | `instance`, `agent` (route name), `prompt` | `id` |
| `result` | `instance`, `id`, `wait_ms` (0 to 600000) | `pending`, or `completed` with `text`, `usage`, `session_id`, `duration_ms`, or `failed` with an error |
| `cancel`, `stop_instance` | `instance`, `id` / `instance` | |

Another `invoke` on the same instance and route continues the same backend
session. Routes default to inherited access (#137).

## Proposed `agent` operation

```
agent(
  prompt,               # required
  session_id?,          # continue this session; omitted: create one
  name?,                # label for a new session
  cwd?,                 # new session's working directory
  provider?,            # claude | codex (server default otherwise)
  model?, effort?,
  access?,              # omitted: inherit; or a narrowing value
  timeout_ms?,          # turn limit; omitted: none
  wait_ms?              # block up to this long for the result
) -> {session_id, invocation_id, status, text?, usage?}
```

- A new `session_id` is an instance with one route, created on the first
  call. Later calls with that `session_id` are turns on the same backend
  session.
- With `wait_ms`, the call returns the terminal result if the turn ends
  within it. Without it, or on expiry, it returns `pending` and the caller
  checks with `result(invocation_id, wait_ms)`.
- `cancel(invocation_id)` stops a turn; `stop(session_id)` ends the session.
- It is an Ops operation, so the Mix task, release RPC and MCP get it from
  the same definition.

## Defaults and why

| Default | Reason |
| --- | --- |
| Inherited access | Native subagents inherit; restricted defaults made agents unable to run checks or reach GitHub (runs 1 to 3). |
| No turn limit | Native subagents have none. GenAgent's 10-minute watchdog stopped a whole-issue turn (run 5). |
| Session kept across calls | The server's addition over native tools: a session outlives the caller's conversation. |
| One route per session | Every procedure run used one provider per turn; multi-route instances added names, not capability. |

## Surfaces and packaging

- Ops is the one definition. The positional CLI and `mix gen_agent_server.remote` duplicate argument handling and should become aliases.
- Surface-specific limits stay per surface: the shared HTTP MCP listener caps waits at 5 s.
- Transport: stdio MCP first, so each client has its own sessions. A shared HTTP instance later, which a stdio client can find or start.
- Packaging follows hexpm-mcp: snodo for MCP, cheer for the CLI, tinfoil and Burrito for a single binary, and an `init` command that installs the plugin for Claude Code and Codex.

## Evidence

| Run | What it showed about the interface |
| --- | --- |
| 1 (codex_wrapper #153) | Session reuse across turns works (19 s revision on the same session). Polling `result` is the main cost. |
| 2 (server #135) | Added `wait_ms` to `result`. Two instances on one worktree. |
| 3 (claude_wrapper #328) | One instance, three routes. A Claude edit route could not run commands. |
| 4 (server #137) | Inherited access by default; a live probe reached the network. |
| 5 (codex_wrapper #154) | One long-lived session per repository, handed a whole issue in one prompt. The 10-minute GenAgent watchdog stopped the first turn after it had pushed and opened a draft PR. With `watchdog_ms: :infinity` (set through `:provider_overrides`), the continuation finished the issue in 19 minutes, CI green. An independent review's findings went back to the same session (same backend session id), which fixed them in 18 minutes. The operator's part was the issue choice, one prompt, the review and verification. |

## Open questions

- Is `session_id` an instance name, or an opaque id the server maps?
- Should `isolation: worktree` exist, or should the prompt or a helper own worktrees?
- Is a message without a turn (Codex `send_message`) needed?
- How much of GenAgent does this need beyond the backend contract and one process per session?

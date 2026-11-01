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

Status: implemented as a spike over the wrappers in #140 and used in run 6. The supported version moves to a wrappers-only library; see "Where it lives".

```
agent(
  prompt,               # required
  session_id?,          # continue this session; omitted: start one
  name?,                # id for a new session (default: generated)
  cwd?,                 # required to start a session
  provider?,            # claude | codex (default codex)
  model?, effort?,
  access?,              # omitted: inherit; or a narrowing value
  wait_ms?              # block up to this long for the result
) -> {session_id, invocation_id, status, text?, usage?, provider_session_id?, duration_ms?}

agent_result(session_id, invocation_id?, wait_ms?)   # latest invocation when omitted
agent_cancel(session_id)                             # running turn and queued prompts
agent_stop(session_id)
agent_sessions()
```

- A new session is one process holding the provider's resume id. Later calls
  with its `session_id` are turns on the same provider session.
- A prompt sent during a turn queues behind it, so a caller can send a
  follow-up without waiting.
- `name`, `cwd`, `provider`, `model`, `effort` and `access` apply only when
  starting a session; passing them with `session_id` is an error rather than
  a silent ignore.
- Invocation ids are `<session_id>/<n>`. `agent_result` without one reads the
  latest, which is how a caller checks on a session it handed work to.
- With `wait_ms`, the call returns the terminal result if the turn ends
  within it; otherwise `pending`.
- No turn limit. The earlier `timeout_ms` parameter is dropped: the caller
  bounds its own wait with `wait_ms` and stops a turn with `agent_cancel`.
- It is an Ops operation, so the Mix task, release RPC and MCP get it from
  the same definition.

## Defaults and why

| Default | Reason |
| --- | --- |
| Inherited access | Native subagents inherit; restricted defaults made agents unable to run checks or reach GitHub (runs 1 to 3). For Claude, inherit means the user's settings, not the creator's mode: with no default mode and no Bash allow rule, a headless session cannot run commands, so run 6 passed `access: auto` to match the creator (run 6). |
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
| 6 (three patterns, #140 spike) | The `agent` call over the wrappers alone carried three issues in parallel to five ready PRs. Single-use (codex_wrapper #156): one call to a ready PR in 17 minutes; its revision went to fresh sessions. Counterpart (codex_wrapper #150): one session for implement, a cross-review of the other PR that found a defect the Claude reviewer missed, and a revision that opened follow-up #173 on its own. Recursive (claude_wrapper #315): a Claude session started its own Codex reviewer through `agent`, ran two review turns on that session and stopped it. Independent Claude reviews still found defects in every PR. |

## How much GenAgent it needs

Traced for #140. The path the procedure runs used:

```
invoke -> Invocations (polls the Ensemble inbox every 100 ms)
       -> GenAgentEnsemble.tell -> GenAgentEnsemble.Server (2322 lines)
       -> Switchboard -> GenAgent.Server (2413 lines) running Agents.Simple (no-op callbacks)
       -> backend adapter (Codex 466 + 352 lines, Claude 364 + 359)
       -> wrapper
```

The spike path:

```
agent -> GenAgentServer.Session (one GenServer per session) -> wrapper Session.send/3 in a task
```

What each layer did for runs 1 to 5:

| Layer | Used | Not used |
| --- | --- | --- |
| Ensemble | name-to-route lookup, inbox | strategies other than Switchboard, fan-out, debate, pipeline |
| GenAgent.Server | one turn at a time, resume id kept in the session, prompt task, watchdog (harmful default) | callbacks, self-chaining, notify, lifecycle hooks |
| Backend adapter | option mapping for fresh and resumed turns, event translation to text and usage, per-turn usage deltas | |
| Wrapper | argv, process, stdin prompt, JSON events | |
| Server `Invocations` | ids, held results, waiters | |

The wrappers already have a `Session` struct that carries the resume id, and a
`SessionServer`. The `SessionServer` blocks in `handle_call` for the whole
turn, so it has no cancel, no status during a turn and no async result. The
spike adds those in about 300 lines.

Gaps the spike found in the released wrappers, each already fixed on the
wrapper's main branch and waiting in a release PR:

| Gap | Wrapper fix | Release PR |
| --- | --- | --- |
| `CodexWrapper.Session` dropped sandbox, approval policy, effort (`-c`) and `ignore_user_config` on resumed turns, and effort on every turn | codex_wrapper #142, #160 | codex_wrapper #165 (0.9.0) |
| `ClaudeWrapper` one-shot path passed `false` env unsets to `System.cmd`, so every turn under the server's child env failed | claude_wrapper #338 | claude_wrapper #332 (0.19.0) |

The GenAgent adapters did not hit either, because they map options and stream
on their own. The adapters held logic that belongs in the wrappers.

Still done by the adapter and not by the spike:

- Codex reports cumulative usage on resumed turns; the adapter reports
  per-turn deltas. The spike passes the cumulative numbers through.
- Streaming events during a turn (activity, tool calls). The spike reports
  only the terminal result.
- HTTP backends (Anthropic, OpenAI). The wrappers cover only the CLIs.

## Patterns to evaluate

Each runs through `agent` on real backlog work and gets a scorecard row.

| Pattern | Shape | What it tests |
| --- | --- | --- |
| Single-use subagent | One `agent` call with a whole issue, `wait_ms` or `agent_result` until done, then `agent_stop` | The native-subagent case: a caller hands off one task and reads one result. |
| Counterpart session | One long-lived session per repository or role, several turns over hours: implement, answer a review, revise, explain | Session reuse, queued follow-ups, the caller and the session working as peers. |
| Recursive | A session started through `agent` starts its own sessions through `agent` (CLI or MCP), for example an implementer starting a reviewer | Inherited access reaching the server itself, session ids passed between agents, no turn limit across levels. |

## Where it lives (plan, 2026-11-01)

Two objectives drive this:

1. **The interface.** One interface that lets an agent or a human create, resume and drive headless Claude or Codex sessions for any task, single-use or ongoing.
2. **The machinery question.** Whether the wrappers plus a thin layer and an MCP surface are enough, without GenAgent in the middle.

The #140 spike answered objective 2 for the turn path, but it lives in gen_agent_server, which depends on GenAgent, Ensemble and both adapters for its instance path. A layer inside that package cannot show it does without them. So the session layer moves out:

| Piece | Depends on | Contents |
| --- | --- | --- |
| Library (name open) | claude_wrapper, codex_wrapper, telemetry | Session registry and supervisor, one process per session, queue, held results and waiters, cancel, stop, adopt by provider session id, ended-session records, cwd check, child environment hygiene. No MCP, no HTTP, no scheduler. |
| Adapter, in the same repository | the library, snodo, cheer, Burrito | The operations as MCP tools (stdio first, then a shared HTTP instance that clients find or start), the same operations as a CLI for humans, and `init`, which installs the plugin for Claude Code and Codex. This follows the hexpm-mcp layout. |
| gen_agent_server | the library | Second consumer: its `agent` operations call the library instead of carrying their own copy. The instance path is unchanged. |

Prior art: `session-fleet-design.md` (local note, 2026-10-18) lists six earlier session managers. Each one was built inside a server and rebuilt by the next. Its conclusion was the manager alone as a library, with adapters on top. Its rule applies here too: stop after the second slice if no second consumer shows up.

### Interface, carried over and refined by runs 1 to 6

- `agent(prompt, session_id?, name?, cwd?, provider?, model?, effort?, access?, wait_ms?, parent_session_id?)`: start or continue a session. Options that apply only at creation are rejected on a continuation.
- `agent(prompt, resume: provider_session_id, ...)`: adopt an existing Claude session id or Codex thread id, so a session outlives the server and any session can be picked up.
- `agent_result(session_id, invocation_id?, wait_ms?)` reads the latest invocation when no id is given.
- `agent_cancel(session_id)`, `agent_stop(session_id)`, `agent_sessions(include_ended?)`.
- Defaults:
  - access inherits, and the doc says what that resolves to for each provider (#143);
  - no turn limit;
  - prompts sent during a turn queue behind it;
  - every session records its parent and depth.

### Slices

1. **Library core.** Extract `GenAgentServer.Session` and its providers from #140. Add the cwd check (#141), ended-session records (#142), adopt by provider id, and the environment hygiene: strip host session variables such as `CLAUDE_CODE_SESSION_ID`, `CODEX_THREAD_ID` and `MIX_*`, and set parent and depth. Use process-group cleanup through Forcola. Covered by fake-CLI tests and an opt-in live test.
2. **Adapter.** MCP stdio tools and a CLI over the same operations, with `@path` for text arguments (#144) and a Burrito binary (#145). Run the three run 6 patterns through it from Claude Code and Codex. The recursive pattern then goes over MCP, not a Mix task.
3. **Second consumer.** gen_agent_server's `agent` operations call the library. #140's own copy is removed.

The objective 2 check: the adapter's release has no GenAgent, Ensemble or adapter in its dependency tree, and it carries the same three patterns as run 6.

## Open questions

- A session's cwd can disappear under it (run 6: a session removed its own worktree; the next turn failed as `{:exit, 2, ""}` with empty stderr). Should `agent` check the cwd per turn and report it by name?
- A stopped session leaves no record, so a session started by another agent is visible only in that agent's report (run 6). Keep a bounded list of ended sessions with their turns' status and duration?
- Should the server pass the caller's access mode explicitly, since it cannot see it?

- Should `isolation: worktree` exist, or should the prompt or a helper own worktrees?
- Is a message without a turn (Codex `send_message`) needed?
- The `agent` path needs one process per session and the wrappers, per the section above. Does anything else in GenAgent earn its place for CLI backends: streaming activity, usage deltas, telemetry?
- `session_id` is a caller-chosen or generated name the server maps to the provider session id. Should sessions survive a server restart by resuming from that provider id?

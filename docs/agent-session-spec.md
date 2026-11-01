# Agent session spec

Status: draft 0.1, 2026-11-01. Derived from the `agent` spike (#140) and procedure runs 1 to 6 ([agent-interface.md](agent-interface.md), [runs](runs/)). Sections 1 to 8 are normative. The appendices are not.

## 1. Goal

This spec defines one interface for creating, resuming and driving headless Claude Code and Codex sessions, for any task and any caller. A caller can be a person at a terminal or another agent, including one started through this same interface. A session may serve a single task and end, or stay open as a long-running counterpart across many turns and conversations. The spec defines the operations and their semantics. It defines two surfaces over the same operations: MCP tools for agents and a CLI for people. It also defines the contract the layer needs from a provider wrapper, the library that runs one CLI turn and carries its session id. The spec is independent of language and runtime. Its working hypothesis is that a provider wrapper plus a thin session layer meets it, with no agent framework in between. The conformance scenarios test that hypothesis, and the implementation stack is chosen from what the spec requires. The behaviour of the existing spike, and the evidence from the procedure runs, are the starting guideline.

## 2. Scope

In:

- Start a session, continue it, adopt an existing provider session, cancel a turn, stop a session, list sessions.
- Hold results so a caller can collect them later, from any conversation.
- Two surfaces, MCP and CLI, over one set of operations.
- Process and environment hygiene for the CLIs the layer starts.
- The capabilities the layer needs from each provider wrapper.

Out (the caller's job or another layer's):

- Orchestration: pipelines, voting, review loops, routing between providers, scheduling. Run 6 built all three of its patterns from these operations without help from the layer.
- Worktrees, branches and pull requests. The prompt or the caller owns them (runs 5 and 6).
- Reading provider session archives, summaries, search.
- Approvals and permission prompts at run time. Access is fixed when a session starts (section 5.8).
- Streaming partial output. Section 9 keeps it as an open question.

## 3. Conventions and concepts

MUST, SHOULD and MAY are used as in RFC 2119. Data shapes are JSON. Durations are integer milliseconds. Times are RFC 3339 UTC strings.

| Term | Meaning |
| --- | --- |
| Provider | A headless agent CLI: `claude` (Claude Code) or `codex` (Codex CLI). |
| Wrapper | A library that runs one provider turn non-interactively and reports its outcome (section 7). |
| Layer | The implementation of this spec: sessions, invocations, results, surfaces. |
| Caller | Whoever calls an operation: a person through the CLI, or an agent through MCP or the CLI. |
| Session | A named, long-lived handle on one provider conversation, with fixed creation options. It runs at most one turn at a time. |
| Session id | The layer's name for a session: chosen by the caller or generated. Pattern `^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$`. |
| Provider session id | The provider's own conversation id: a Claude session id or a Codex thread id. It survives the layer. |
| Invocation | One prompt submitted to a session. Its id is `<session_id>/<n>`, with `n` counting from 1. |
| Turn | The provider run that serves one invocation. |
| Access | What the provider may do: `inherit` or a narrowing value (section 5.8). |
| Parent | The session that started this one, when a session calls the layer itself. Depth is the number of ancestors. |
| Ended session | A stopped session, kept as a bounded record (section 5.11). |

## 4. Operations

Five operations. Every surface MUST offer all five with the same names, parameters, results and errors (section 6).

### 4.1 `agent`

Start a session and submit a prompt, or submit a prompt to an existing session.

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `prompt` | string, required | | Task or message. No size limit at this layer. |
| `session_id` | string | | Continue this session. Omit to start one. |
| `name` | string | generated | Session id for a new session. |
| `resume` | string | | Provider session id to adopt when starting a session (section 5.7). |
| `cwd` | string | | Absolute working directory. Required when starting. |
| `provider` | `claude` or `codex` | layer default | |
| `model` | string | the CLI's | |
| `effort` | string | the CLI's | Provider-specific values (section 5.8). |
| `access` | string | `inherit` | Section 5.8. |
| `parent_session_id` | string | | Session that is starting this one (section 5.12). |
| `wait_ms` | integer, 0 to 600000 | 0 | Wait this long for the invocation to end. |

`name`, `resume`, `cwd`, `provider`, `model`, `effort`, `access` and `parent_session_id` apply only when starting a session. Passing any of them with `session_id` MUST fail with `invalid_args` naming them (section 5.6).

Result: an invocation object (section 4.6).

### 4.2 `agent_result`

| Parameter | Type | Default |
| --- | --- | --- |
| `session_id` | string, required | |
| `invocation_id` | string | the session's latest invocation |
| `wait_ms` | integer, 0 to 600000 | 0 |

Result: an invocation object. Reading a result does not consume it. The same id returns the same terminal result until it is evicted (section 5.15).

### 4.3 `agent_cancel`

| Parameter | Type |
| --- | --- |
| `session_id` | string, required |

Cancels the running turn and every queued invocation of the session. The session stays open and accepts new prompts. Result: `{session_id, cancelled: [invocation_id], cleanup}`, where `cleanup` is `confirmed`, `unknown` or `none` (nothing was running) (section 5.10).

### 4.4 `agent_stop`

| Parameter | Type |
| --- | --- |
| `session_id` | string, required |

Cancels any running and queued invocations, ends the session and moves it to the ended records. Result: `{session_id, stopped: true, cancelled: [invocation_id]}`. Stopping an ended session returns `session_not_found`.

### 4.5 `agent_sessions`

| Parameter | Type | Default |
| --- | --- | --- |
| `include_ended` | boolean | false |
| `parent_session_id` | string | |

Result: `{sessions: [session]}`, sorted by session id. With `parent_session_id`, only the children of that session.

### 4.6 Objects

**Invocation.**

```json
{
  "session_id": "review-315",
  "invocation_id": "review-315/2",
  "status": "completed",
  "text": "final message of the turn",
  "usage": {"input_tokens": 1200, "output_tokens": 340, "cached_input_tokens": 900, "reasoning_output_tokens": 40},
  "cost_usd": 0.42,
  "provider_session_id": "0a8c3b19-...",
  "submitted_at": "2026-11-01T14:21:03Z",
  "started_at": "2026-11-01T14:21:03Z",
  "ended_at": "2026-11-01T14:23:47Z",
  "duration_ms": 164000,
  "error": null
}
```

- `status` is one of `queued`, `running`, `completed`, `failed` or `cancelled`. The first two are pending; the last three are terminal.
- `text` is the provider's final message, present when `completed`.
- `usage` covers this turn only (section 5.14). It holds the counters the provider reports. A counter the provider does not report is absent, not zero.
- `cost_usd` is present only when the provider reports cost.
- `error` is an error object (section 4.7) when `failed`.

**Session.**

```json
{
  "session_id": "counterpart-codex-wrapper",
  "state": "idle",
  "provider": "codex",
  "provider_session_id": "01a19753-...",
  "cwd": "/abs/path",
  "cwd_exists": true,
  "model": null,
  "effort": null,
  "access": "inherit",
  "access_resolved": "provider default from the user's CLI configuration",
  "parent_session_id": null,
  "depth": 0,
  "created_at": "2026-11-01T13:36:41Z",
  "last_activity_at": "2026-11-01T14:17:27Z",
  "running": null,
  "queued": 0,
  "completed": 3,
  "failed": 0,
  "cancelled": 0,
  "latest": "counterpart-codex-wrapper/3",
  "usage_total": {"input_tokens": 0, "output_tokens": 0},
  "cost_usd_total": null
}
```

`state` is `idle`, `running` or `ended`. Ended sessions also carry `ended_at`, `end_reason` (`stopped` or `failed`) and their invocation summaries (section 5.11).

### 4.7 Errors

An error object is `{code, message, detail?}`. `code` is from the table below. `message` is one human-readable sentence. `detail` is an object with provider facts (exit status, the stderr tail, a signal), never the prompt or the credentials.

| Code | When |
| --- | --- |
| `invalid_args` | Missing, unknown or ill-typed parameters, or creation-only parameters with `session_id`. |
| `invalid_option` | A value outside its allowed set: `provider`, `effort`, `access`. `detail.option` names it. |
| `session_not_found` | No live session with that id. |
| `session_exists` | `name` is already a live session. |
| `invocation_not_found` | No such invocation, or it was evicted. |
| `cwd_missing` | The working directory does not exist when starting a session or a turn (section 5.9). |
| `resume_not_found` | The provider has no session with the `resume` id. |
| `too_many_sessions` | Starting a session would exceed the live-session limit. |
| `queue_full` | The session's queue is at its limit. |
| `provider_unavailable` | The CLI binary is missing or cannot start. |
| `turn_failed` | The provider ran and reported failure. `detail` has the provider's failure. |
| `provider_exit` | The CLI exited nonzero without a terminal report. `detail` has the exit status and the stderr tail. |
| `cancelled` | The invocation was cancelled. |

Operations return errors for requests the layer rejects. Turn failures are not operation errors. They appear as a `failed` invocation with its `error`.

## 5. Semantics

Each rule names the run that led to it.

**5.1 One turn at a time.** A session MUST run at most one turn at a time. Provider conversations are sequential, and two concurrent turns on one provider session id would fork it.

**5.2 Queueing.** A prompt submitted while a turn runs MUST queue behind it, in submission order, and return its invocation id at once. A caller can send a follow-up without waiting (run 6, counterpart).

**5.3 Turns outlive their caller.** A turn MUST run independently of the call that submitted it. If the caller disconnects, its wait expires or its process exits, the turn continues and its result is held. This is what lets a session outlive the conversation that started it (runs 5 and 6).

**5.4 Waiting.** `wait_ms` bounds how long a call blocks. When it expires, the call returns the invocation with a pending status, and the turn continues. A surface MAY cap `wait_ms` lower than 600000 (section 6), and MUST say so in its schema. Polling with short waits is a fallback, not the design (run 1: seven polls for one turn).

**5.5 No turn limit.** The layer MUST NOT impose a turn duration limit by default. Native subagents have none, and a 10-minute default ended a whole-issue turn (run 5). A turn ends when the provider finishes, fails or is cancelled. A wrapper's idle or whole-run timeouts MUST be off, or set from explicit configuration.

**5.6 Creation-only options.** Options that shape a session (`name`, `resume`, `cwd`, `provider`, `model`, `effort`, `access`, `parent_session_id`) are fixed when the session starts. Passing them with `session_id` MUST fail rather than be ignored. A caller who wants different options starts another session.

**5.7 Adopting a provider session.** With `resume`, a new session continues an existing provider conversation: the Claude session id or the Codex thread id. This is how a session survives a layer restart, and how a caller picks up a session started anywhere else (a terminal, the desktop app, another layer). The layer MUST check, through the wrapper, that the provider session exists before accepting the call, or MUST fail the first turn with `resume_not_found`. The adopted session's usage totals start at zero.

**5.8 Access.** `access` fixes what the provider may do for the life of the session, on every turn including resumed ones (run 6: codex_wrapper dropped the sandbox on resumed turns until #142).

| Value | Claude | Codex |
| --- | --- | --- |
| `inherit` (default) | No permission or tool flags. The CLI applies the user's settings. | No sandbox flag. The CLI applies the user's configuration. Approval prompts disabled. |
| `read_only` | Read-only tools, no approval prompts. | Read-only sandbox. |
| `workspace_write` | not offered | Workspace-write sandbox. |
| A Claude permission mode (`plan`, `accept_edits`, `auto`, `dont_ask`, `bypass_permissions`) | That mode. | not offered |

Values a provider does not offer MUST fail with `invalid_option`. `inherit` means the user's provider configuration, not the caller's mode. The layer cannot see the caller's mode. A caller that wants a child to match its own mode MUST pass that mode. For Claude, `inherit` under settings that allow no shell commands produces a session that cannot run commands headless (runs 3 and 6). The session object reports this in `access_resolved` when the layer can determine it.

**5.9 Working directory.** `cwd` MUST be absolute and exist when the session starts. Before each turn the layer MUST check it again. If it is missing, the invocation fails with `cwd_missing` and the CLI is not started (run 6: a session deleted its own worktree, and its next turn failed as an opaque exit 2).

**5.10 Cancel.** Cancelling MUST stop the turn's whole process tree: the CLI, the tools it started and their children. The layer MUST NOT report `cleanup: confirmed` unless the wrapper confirmed that the tree has exited. Otherwise it reports `unknown`. A cancelled invocation has status `cancelled`. Queued invocations are cancelled without starting.

**5.11 Ended sessions.** `agent_stop` and an unrecoverable session failure move a session to a bounded set of ended records, default 100, oldest evicted first. Each record keeps the session object and one summary per invocation: id, status, timestamps, duration, usage, cost and error code. It keeps no prompt or response text. Ended records answer `agent_sessions` with `include_ended` and `agent_result` for their invocations' status. A session started by another agent can then be accounted for after it stops (run 6: two self-started reviewers left no trace).

**5.12 Nesting.** A session can call the layer, through either surface, to start sessions of its own (run 6, recursive). The layer MUST make this possible and visible:

- Each turn's environment carries the session id, the depth and the layer's address (section 5.13), so a child can call back without configuration.
- `parent_session_id` defaults from that environment when the caller is a session.
- The layer MUST enforce a maximum depth, default 3, with `invalid_args`.

**5.13 Child environment.** The CLI's environment is the layer's environment with these changes, applied in order:

1. Remove variables that belong to the layer's own runtime or host, and would change the behaviour of tools the agent runs. That covers a release's boot variables and `PATH` entries (codex_wrapper #156, run 6). It also covers variables that mark the parent as an agent session, such as `CLAUDECODE` and `CLAUDE_CODE_*` session markers, Codex thread markers, and build-tool output switches such as `MIX_QUIET` (run 6).
2. Add the session id, the depth and the layer's address.
3. Apply trusted operator overrides from configuration. Callers cannot set environment variables.

Credentials in the environment pass through unchanged and are never copied into results or logs.

**5.14 Usage per turn.** `usage` on an invocation MUST cover that turn alone. Providers that report a running total for the conversation (Codex reports `turn.completed.usage` as the thread's total, including on resumed turns) are converted by subtracting the previous total. A counter that goes missing or decreases yields no value for that turn. The first turn of an adopted session reports no usage, because no previous total is known. `usage_total` on the session is the sum of per-turn values.

**5.15 Limits and retention.**

- Live sessions: default 32, `too_many_sessions` beyond it.
- Queued invocations per session: default 16, `queue_full` beyond it.
- Held results per session: default 100, evicted oldest first. Pending invocations are never evicted.

All three are operator configuration, not call parameters.

**5.16 Restart.** A layer restart ends its live sessions and their running turns. A turn interrupted by a restart MUST NOT be resent automatically. The provider sessions survive, so a caller recovers with `agent` and `resume` (section 5.7). Persisting live sessions across a restart is not required (section 9).

**5.17 Secrets and content.** The layer MUST NOT log prompts or response text by default. Telemetry and ended records carry ids, statuses, durations, usage and error codes only.

## 6. Surfaces

### 6.1 Equivalence

Every surface exposes the five operations in section 4 with the same parameter names, types, defaults, results and error codes. A surface MAY add limits it documents, such as a lower `wait_ms` cap. A surface MUST NOT add semantics: everything in section 5 holds whichever surface the caller uses.

### 6.2 MCP

- One tool per operation, named as in section 4. The input schema is the parameter table as JSON Schema with `additionalProperties: false`.
- The result is the operation's JSON result as structured content, plus a short text rendering. An operation error is a tool error carrying the error object.
- Transports:
  - **stdio.** One layer per client process. Sessions live as long as that process.
  - **Shared HTTP.** One layer per user per machine, reachable from every client, so sessions outlive any one client. A stdio client MAY proxy to a shared instance it finds at a documented address, or start one. The shared transport MAY cap `wait_ms`, and MUST say so in its schema (run 2: the shared listener caps waits at 5 s).
- A plugin for Claude Code and Codex installs the MCP server configuration (`init` in section 6.3).

### 6.3 CLI

- One command per operation, `<tool> agent`, `<tool> agent-result` and so on. Each parameter is a long option with its name: `--session-id`, `--wait-ms`.
- Any string parameter accepts `@path` to read the value from a file, and `@-` for stdin. `@@` escapes a literal leading `@` (run 6: a prompt built in an unquoted shell heredoc lost three phrases to command substitution).
- Output is the JSON result on stdout. Errors exit nonzero with the error object on stderr.
- The CLI talks to a running shared layer when one is reachable. Otherwise it fails with a message naming how to start one. It does not start a layer for a single command, because sessions would end with the command.
- `<tool> serve` starts a layer. `<tool> init` installs the MCP plugin for Claude Code and Codex.
- The CLI MUST start in well under a second and run concurrently with itself, so that waits from parallel callers do not block on each other (run 6: Mix build-lock contention).

### 6.4 Host integration: plugin, skill and hooks

Facts about Claude Code 2.1.312 and Codex CLI 0.163.0 come from the plugins and hooks cookbook (reviewed 2026-10-28, [gist](https://gist.github.com/joshrotenberg/fe344b88bdfbbeef3ad39d709c2a69fe)). Re-check them on each host release.

**One plugin for both hosts.** `init` installs a single plugin that carries:

| Component | Claude Code | Codex |
| --- | --- | --- |
| Manifest | `.claude-plugin/plugin.json` | root `plugin.json` (portable format), with hooks under `extensions["com.openai"]` |
| MCP server | `.mcp.json` | root `mcp.json`; each entry needs `type` |
| CLI | `bin/` is put on the Bash tool's `PATH` | no automatic `PATH`; skills and hooks use the packaged absolute path |
| Skill | `skills/<name>/SKILL.md` | same file |
| Hooks | `hooks/hooks.json` | same shape, declared in the root manifest |

- Install through each host's marketplace commands (`claude plugin marketplace add` and `install`; `codex plugin marketplace add` and `plugin add`), never by editing host settings directly. Codex reviews and trusts each hook by its hash in `/hooks`, so `init` must tell the user to do this, and a changed hook needs review again.
- Mutable state, including the shared instance's address (section 9, question 6), lives in the host's plugin data directory (`CLAUDE_PLUGIN_DATA` or `PLUGIN_DATA`), not in the plugin root, which updates replace.
- Claude Code exposes plugin MCP tools as `mcp__plugin_<plugin>_<server>__<tool>`. Skills and hook matchers use that name.
- Surfaces that reject plugins carrying `bin/` (claude.ai, Cowork) get the MCP server only.

**Skill.** The plugin carries one skill that teaches when to use the operations instead of the host's native subagent tool. Use them for work that must outlive the conversation, for a counterpart on another provider, or for a session another agent will pick up. It also teaches the three patterns in section 8, and the fallback when the plugin's hooks are disabled. It contains instructions only. Enforcement belongs in the layer.

**Hooks.** All hooks are optional, and the operations work without them. Each uses only the events and fields that both hosts share, unless marked otherwise.

| Hook | Event | What it does | Why |
| --- | --- | --- | --- |
| Completion notice | Claude Code: a monitor, or a background hook with `asyncRewake`. Codex: a background hook (delivered at the next safe point; it does not wake an idle session). | When an invocation the caller submitted reaches a terminal status, tell the caller its id and status. | Native subagents push their result to the parent. Without a notice, callers poll (run 1). |
| Caller mode | `SessionStart` and `SubagentStart`; both hosts put `permission_mode` in hook input | Record the caller's session id and permission mode in plugin data, where the layer reads them as the default `access` and `parent_session_id` for sessions that caller starts. | The layer cannot otherwise see the caller's mode (section 5.8, #143). |
| Brief | `SessionStart`, sources `startup`, `resume` and `compact` | Print a factual list of the caller's live and recently ended child sessions, with pending invocation ids, under 1,500 characters. | Lets a caller that compacted or resumed find the sessions it started. |
| Check once at the end | `Stop`, with `stop_hook_active` respected | If the caller has pending child invocations it never read, block once and name them. | Unread results are lost work. Block at most once, so the hook never loops. |

Rules for these hooks:

- No hook makes network calls on `PreToolUse`, or blocks on the layer for more than its event's timeout. `SessionEnd` gets 1 to 3 seconds on Codex and 1.5 seconds by default on Claude Code, so child sessions MUST NOT depend on `SessionEnd` for cleanup. A child outlives its caller by design (section 5.3).
- Hook output states facts and never echoes prompts, results or credentials.
- A missing binary or an unreachable layer fails open with a `systemMessage`, because every hook here is advisory.

**Child sessions run the user's own hooks and plugins.** Under `inherit`, a child session loads the user's hooks, plugins and instructions like any session. The child's environment marks it as a child (section 5.12), so a user's `SessionStart` brief or `Stop` gate can tell a headless child from an interactive session and skip work meant for people. Claude Code does not run project subagent hooks in `-p` mode until workspace trust is accepted, so child sessions see only user and plugin hooks there.

## 7. Wrapper contract

What the layer needs from a provider wrapper, as capabilities. A wrapper may be a library in the layer's language or a process the layer calls. Appendix A maps the current Elixir wrappers.

| Id | Capability | Needed by |
| --- | --- | --- |
| W1 | Run one turn non-interactively, either fresh or resuming a provider session id. Return a terminal outcome: status, final message, provider session id, usage as reported, cost when reported. | `agent` |
| W2 | Report the provider session id as soon as the provider emits it, before the turn ends. | 5.3, 5.10, 5.16: an interrupted first turn stays resumable |
| W3 | Apply the same model, effort and access options on fresh and resumed turns. | 5.6, 5.8 |
| W4 | Express `inherit` by passing no access flags, and express each narrowing value in section 5.8. | 5.8 |
| W5 | Cancel a running turn, terminate the CLI's whole process tree, and report whether termination was confirmed. | 5.10 |
| W6 | Set and unset child environment variables per turn, with unsets honoured on every spawn path. | 5.12, 5.13 |
| W7 | Deliver the prompt without an argv size limit (stdin or a file), and keep it out of the process table. | 4.1: no prompt size limit; 5.17 |
| W8 | Run each turn in a given working directory. | 5.9 |
| W9 | Impose no turn timeout unless configured. | 5.5 |
| W10 | Distinguish these failures, each with the provider's detail (exit status, the stderr tail): missing binary or spawn failure, provider-reported failure, nonzero exit without a report, cancellation. | 4.7 |
| W11 | Report per-turn usage, or report running totals with documented semantics, so the layer can apply 5.14. | 5.14 |
| W12 | Check whether a provider session id exists, without running a turn. | 5.7 |

Optional: W13, steer or interrupt a turn without ending it. The current operations do not use it (section 9).

A wrapper gap MUST be fixed in the wrapper, not worked around in the layer. Run 6 found two gaps of this kind, codex_wrapper #142 and claude_wrapper #338. Both were already fixed upstream, and both had been hidden by logic that the GenAgent adapters carried themselves.

## 8. Conformance

An implementation conforms when it passes these, against fake CLIs in automated tests and against the real CLIs in a live smoke run.

| Id | Scenario | Checks |
| --- | --- | --- |
| C1 | Single-use: one `agent` call with a whole task, `agent_result` until terminal, `agent_stop`. | Terminal result, ended record present, no process left. |
| C2 | Counterpart: one session, three turns, plus a follow-up sent while the second turn runs. | The same provider session id on every turn, queue order, per-turn usage. |
| C3 | Recursive: a session starts a child session through the MCP surface, which runs two turns and is stopped by its parent. | The child's `parent_session_id` and depth, the child in `agent_sessions` with `include_ended`. |
| C4 | Restart: stop the layer mid-session, start it, then `agent` with `resume` set to the provider session id. | The conversation continues, and the interrupted turn is not resent. |
| C5 | Cancel: cancel a turn whose CLI has started a long-running child process. | The process tree has exited when `cleanup` is `confirmed`. |
| C6 | Working directory: remove the cwd between turns. | `cwd_missing`, CLI not started, session still usable after the directory returns. |
| C7 | Access: a `read_only` session's resumed turn. | The narrowing applies on the resumed turn. |
| C8 | Usage: two turns on a provider that reports running totals. | The second turn's usage is the difference. |
| C9 | Environment: a turn in a layer started from a release, from inside an agent session, with `MIX_QUIET` set. | The child sees none of the variables in 5.13 step 1, and does see the session id and depth. |
| C10 | Surfaces: run C1 to C3 through MCP and through the CLI. | Identical results and error codes. |
| C11 | Dependencies: list the implementation's dependency tree. | Nothing between the layer and the wrappers but the runtime's standard library and the surface libraries. |
| C12 | Host integration: install the plugin with `init` on Claude Code and on Codex, then run C1 from each host through the MCP tools. | The tools are listed under the plugin's names. A completion notice reaches the caller. The child's `access` defaults to the caller's recorded mode. Disabling the plugin's hooks leaves the operations working. |

C11 is the check for the working hypothesis in section 1.

## 9. Open questions

1. **Streaming.** Should `agent_result` offer partial output, or a progress summary (last activity, tool calls so far), while a turn runs? Native subagents report only at the end. Run 6 never needed more, but a person watching a long turn might.
2. **Steering.** Should a prompt sent during a turn be able to steer it (W13) rather than queue? Codex's app server and Claude's duplex mode can. That needs a live check, and a decision on whether it is a parameter of `agent` or a separate operation.
3. **Persistence.** Should live sessions persist across a restart as dormant handles (sessions resumed by provider id on their next prompt), rather than relying on callers to `resume`?
4. **Isolation.** Should the layer offer a worktree per session, as Claude Code's subagent `isolation: worktree` does, or leave it to prompts as in runs 5 and 6?
5. **Messages without a turn.** Codex's `send_message` delivers text without starting a turn. Is that needed?
6. **Discovery.** How a stdio client finds a shared instance. The leading option is an address file in the plugin data directory (section 6.4), with a fixed local address as the fallback.
7. **Caller mode.** The caller-mode hook (section 6.4) can supply the mode. Should a recorded mode become the default `access`, or only be reported for the caller to pass (#143)?
9. **Native subagent routing.** Should a `PreToolUse` hook on the host's own subagent tool (`Agent`, `spawn_agent`) offer the layer instead? The current answer is no: rewriting a tool call the model chose is invisible to it, and the cookbook lists that as an anti-pattern. The skill (section 6.4) teaches when to choose the layer.
8. **Budgets.** Whether the layer should enforce cost or token budgets per session or across sessions, or leave that to callers.

## Appendix A. Mapping to the Elixir wrappers (non-normative)

As of claude_wrapper 0.19.0 and codex_wrapper 0.9.0, with codex_wrapper main noted where it differs.

| Id | claude_wrapper 0.19.0 | codex_wrapper 0.9.0 (main) |
| --- | --- | --- |
| W1 | Met. `Session.send/3` runs `claude -p`, with `--resume` from the second turn; `Result` has `result`, `session_id`, `cost_usd`, `usage`, `is_error`. | Met. `Session.send/3` runs `exec`, then `exec resume <thread_id>`. Main adds `CodexWrapper.Turn` with status, final message, thread id and usage. |
| W2 | Partial. `Query.execute/3` takes a `:session_observer` that reports the id at `system/init`; `Session.send/3` does not expose it. The pending `ClaudeWrapper.Run` (#351) does. | Partial. `thread.started` carries the id; `Session.send/3` reports it only after the turn. |
| W3 | Met. Session query options apply to every turn. | Met since 0.9.0 (#142, #160). |
| W4 | Met: `permission_mode`, `tools`. | Met: `sandbox`, `approval_policy`, `ignore_user_config`. |
| W5 | Partial. The default Port runner signals the CLI when its owner dies but not its process group. `Runner.Forcola` kills the group, selected by application configuration. `ClaudeWrapper.Run` (#351, open) adds cancel with recorded evidence; cleanup is `unknown` with Forcola 0.7. | Partial. Same Port and Forcola split. No async handle. |
| W6 | Met for set and unset (`false`, #338). Release scrub since #340. Agent-session markers and build-tool switches are not scrubbed. | Met for set and unset (#162). Release scrub on main (#170, #174, unreleased). The same markers are not scrubbed. |
| W7 | Met. Prompts go on stdin by default (`prompt_input`). | Met since 0.9.0 (#169). |
| W8 | Met. `Config.working_dir`. The existence check is the layer's. | Met. `Config.working_dir`. |
| W9 | Met. One-shot runs have no timeout unless `Config.timeout` is set. | Met for `Session.send/3`. Streaming and evidenced paths default to a 300 s idle bound. |
| W10 | Met. `%ClaudeWrapper.Error{}` kinds. | Partial. `{:exit, code, result}` and `{:spawn, reason}`. In run 6 a missing cwd produced exit 2 with empty stderr. |
| W11 | Met. Per invocation. | Gap. The CLI reports running totals. On main, `Session.total_usage/1` adds each turn's running total, so it overcounts from the second turn on. #173 builds on it. |
| W12 | Gap. No existence check for a session id. | Gap. No existence check for a thread id. |

## Appendix B. The spike against this spec (non-normative)

#140 (`GenAgentServer.Session`, `GenAgentServer.Ops.Agent`) implements 4.1 to 4.5 without `resume`, `parent_session_id` or `include_ended`, and covers 5.1 to 5.6. Where it differs:

| Rule | Spike |
| --- | --- |
| 4.6 | Invocation ids and statuses match, except that `queued` and `running` are both reported as `pending`. No timestamps beyond `duration_ms`. |
| 4.7 | Some errors are inspected tuples with code `error`. |
| 5.7 | No `resume`. |
| 5.9 | The cwd is checked only by the provider configuration at start. |
| 5.10 | Cancel kills the turn task; with the Port runner the CLI's children can survive. No `cleanup` field. |
| 5.11 | `agent_stop` discards everything. |
| 5.12 | The environment carries neither the session id nor the depth; the recursive run passed node and environment by prompt. |
| 5.13 | Release variables are scrubbed by the server's child environment; agent-session markers and `MIX_QUIET` are not. |
| 5.14 | Codex usage is passed through as running totals. |
| 5.15 | Held results are bounded per session; there are no session or queue limits. |
| 6.3 | The CLI is `mix gen_agent_server.ops`, from a server checkout, without `@path`. |

## Appendix C. Native subagent tools (non-normative)

The operations are shaped after the subagent tools Claude Code and Codex give their own sessions; see [agent-interface.md](agent-interface.md) for the comparison. The additions over them are a session that outlives the caller's conversation (5.3), held results readable from anywhere (4.2), adopting provider sessions (5.7), and ended records (5.11). As in both native tools, a call has no permission parameter beyond `access`, and there is no turn limit.

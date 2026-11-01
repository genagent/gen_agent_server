# Agent session spec

Status: draft 0.2, 2026-11-01. Derived from the `agent` spike (#140) and procedure runs 1 to 6. The history and evidence are in [agent-interface.md](agent-interface.md) and in the run records on the `docs/issue-process` branch (#134). Draft 0.1 was reviewed by one Claude and one Codex session; Appendix D lists what changed.

Sections 1 to 9 are normative, except where a section says otherwise. Section 10 and the appendices are not normative.

## 1. Goal

This spec defines one interface for creating, resuming and driving headless Claude Code and Codex sessions, for any task and any caller. A caller can be a person at a terminal or another agent, including one started through this same interface. A session may serve a single task and end, or stay open as a long-running counterpart across many turns and conversations. The spec defines the operations and their semantics. It defines two surfaces over the same operations: MCP tools for agents and a CLI for people. It also defines the contract the layer needs from a provider wrapper, the library that runs one CLI turn and carries its session id. The spec is independent of language and runtime. Its working hypothesis is that a provider wrapper plus a thin session layer meets it, with no agent framework in between. The conformance scenarios and the evaluation in section 10 test that hypothesis, and the implementation stack is chosen from what the spec requires. The behaviour of the existing spike, and the evidence from the procedure runs, are the starting guideline.

## 2. Scope

In:

- Start a session, continue it, adopt an existing provider session, cancel a turn, stop a session, list sessions, describe the layer.
- Hold results so a caller can collect them later, from any conversation.
- One long-lived layer per user per machine, reached by every surface.
- Process and environment hygiene for the CLIs the layer starts.
- The capabilities the layer needs from each provider wrapper.
- An optional host-integration profile: a plugin, a skill and hooks for Claude Code and Codex (section 7).

Out (the caller's job or another layer's):

- Orchestration: pipelines, voting, review loops, routing between providers, scheduling. Run 6 built all three of its patterns from these operations without help from the layer.
- Worktrees, branches and pull requests. The prompt or the caller owns them (runs 5 and 6).
- Reading provider session archives, summaries, search.
- Approvals and permission prompts during a turn. Access is fixed when a session starts (section 5.10).
- Streaming partial output (section 11).
- Remote access from other machines or other users.

## 3. Conventions and concepts

MUST, SHOULD and MAY are used as in RFC 2119. Data shapes are JSON. A field with no value is absent: implementations MUST NOT emit `null`. Durations are integer milliseconds. Times are RFC 3339 UTC strings.

| Term | Meaning |
| --- | --- |
| Provider | A headless agent CLI: `claude` (Claude Code) or `codex` (Codex CLI). |
| Wrapper | A library that runs one provider turn non-interactively and reports its outcome (section 8). |
| Layer | The implementation of this spec: one long-lived service per user per machine that owns sessions, invocations and results. |
| Surface | A client of the layer: the MCP server or the CLI (section 6). Surfaces hold no sessions of their own. |
| Caller | Whoever calls an operation: a person through the CLI, or an agent through MCP or the CLI. |
| Session | A handle on one provider conversation, with options fixed at creation. It runs at most one turn at a time. |
| Session id | The session's id: chosen by the caller (`name`) or generated. Pattern `^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$`. Unique for the lifetime of the layer process (section 5.2). |
| Provider session id | The provider's own conversation id: a Claude session id or a Codex thread id. It survives the layer. |
| Owner | The session that currently drives a provider session id in this layer (section 5.3). |
| Invocation | One prompt accepted by a session. Its id is `<session_id>/<n>`, with `n` counting from 1 and never reused. |
| Turn | The provider run that serves one invocation. |
| Access | What the provider may do: `inherit` or a narrowing value (section 5.10). |
| Parent | The layer session that started this one, when a session calls the layer itself. Depth is the parent's depth plus one; a session with no parent has depth 0. |
| Caller id | Optional opaque metadata naming the caller outside the layer, for example a host conversation id (section 5.14). It is not a session id. |
| Ended session | A session that will run no more turns. It keeps its held results until evicted (section 5.13). |

## 4. Operations

Six operations. Every surface offers all six (section 6.1).

### 4.1 `agent`

Start a session and submit a prompt, or submit a prompt to an existing session.

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `prompt` | string, required | | Task or message. No size limit at this layer. |
| `session_id` | string | | Continue this session. Omit to start one. |
| `name` | string | generated | Session id for a new session. |
| `resume` | string | | Provider session id to adopt when starting (section 5.9). |
| `cwd` | string | | Absolute working directory. Required when starting. |
| `provider` | string | from `agent_info` | One of `agent_info.providers`. |
| `model` | string | the CLI's | |
| `effort` | string | the CLI's | One of `agent_info.providers[].efforts`. |
| `access` | string | `inherit` | One of `agent_info.providers[].access` (section 5.10). |
| `parent_session_id` | string | from the environment | Section 5.14. |
| `caller_id` | string | | Section 5.14. |
| `request_id` | string | | Idempotency key (section 5.6). |
| `wait_ms` | integer, 0 to 600000 | 0 | Wait this long for the submitted invocation to end. |

`name`, `resume`, `cwd`, `provider`, `model`, `effort`, `access`, `parent_session_id` and `caller_id` apply only when starting a session. Passing any of them with `session_id` MUST fail with `invalid_args` naming them (section 5.8).

Result: the submitted invocation (section 4.7).

### 4.2 `agent_result`

| Parameter | Type | Default |
| --- | --- | --- |
| `session_id` | string, required | |
| `invocation_id` | string | the session's latest invocation |
| `wait_ms` | integer, 0 to 600000 | 0 |

"Latest" is the invocation with the highest `n`, whatever its status, resolved once when the call is accepted. Result: the invocation. Reading a result does not consume it. The same id returns the same terminal result until it is evicted (section 5.13). Works on live and ended sessions.

### 4.3 `agent_cancel`

| Parameter | Type |
| --- | --- |
| `session_id`, required | string |

Cancels the running turn and every queued invocation accepted before this call (section 5.4). The session stays open. Result: `{session_id, cancelled: [invocation_id], cleanup}`. `cancelled` lists only the invocations this call moved to `cancelled`. `cleanup` is `confirmed`, `pending` (section 5.12) or `none` when no turn was running.

### 4.4 `agent_stop`

| Parameter | Type |
| --- | --- |
| `session_id`, required | string |

Cancels the session's running and queued invocations as `agent_cancel` does, rejects later submissions, and ends the session. Result: `{session_id, stopped: true, cancelled: [invocation_id], cleanup}`. Stopping a session does not stop its children (section 5.14). Stopping an ended session fails with `session_ended`.

### 4.5 `agent_sessions`

| Parameter | Type | Default |
| --- | --- | --- |
| `include_ended` | boolean | false |
| `parent_session_id` | string | |
| `caller_id` | string | |

Result: `{sessions: [session]}`, sorted by session id. The filters are combined with AND.

### 4.6 `agent_info`

No parameters. Result:

```json
{
  "spec_version": "0.2",
  "layer_version": "...",
  "providers": [
    {"name": "claude", "efforts": ["low", "medium", "high", "xhigh", "max"], "access": ["inherit", "read_only", "plan", "accept_edits", "auto", "dont_ask", "bypass_permissions"], "available": true},
    {"name": "codex", "efforts": ["low", "medium", "high"], "access": ["inherit", "read_only", "workspace_write"], "available": true}
  ],
  "default_provider": "codex",
  "limits": {"max_sessions": 32, "max_queued": 16, "max_results": 100, "max_ended": 100, "max_depth": 3, "idle_ms": 86400000, "cleanup_ms": 30000},
  "surface": {"name": "mcp", "max_wait_ms": 600000}
}
```

The values shown are examples. `available` is false when the CLI binary is missing. `surface` describes the surface answering the call.

### 4.7 Objects

**Invocation.**

| Field | Presence | Meaning |
| --- | --- | --- |
| `session_id`, `invocation_id` | always | |
| `status` | always | `queued`, `running`, `completed`, `failed` or `cancelled`. The first two are pending; the rest are terminal. |
| `submitted_at` | always | When the layer accepted it. |
| `started_at` | once the turn started | |
| `ended_at` | when terminal | |
| `duration_ms` | when terminal and started | `ended_at` minus `started_at`. Queue time is excluded. |
| `provider_session_id` | once known | Reported as soon as the wrapper reports it (W2), including while `running`. |
| `text` | when `completed` | The provider's final message. Possibly empty. |
| `usage` | when known | This turn only (section 5.15). Counters the provider does not report are absent. |
| `cost_usd` | when the provider reports cost | This turn only. |
| `error` | when `failed` or `cancelled` | An error object (section 4.8). |
| `delivered` | always | True once a terminal result for this invocation has been returned to any caller. |

**Session.**

| Field | Presence | Meaning |
| --- | --- | --- |
| `session_id`, `provider`, `cwd`, `access`, `depth`, `created_at` | always | |
| `state` | always | `idle`, `running`, `cleaning` (section 5.12) or `ended`. |
| `provider_session_id` | once known | |
| `model`, `effort` | when given at creation | |
| `parent_session_id`, `caller_id` | when set | |
| `cwd_exists` | always on live sessions | Checked when the session is described. |
| `last_activity_at` | always | Last submission or terminal transition. |
| `running` | while a turn runs | Its invocation id. |
| `queued`, `completed`, `failed`, `cancelled` | always | Counts over the session's life, including evicted invocations. |
| `latest` | once an invocation exists | |
| `usage_total` | when any turn reported usage | Sum of per-turn usage. |
| `cost_usd_total` | when any turn reported cost | |
| `ended_at`, `end_reason` | when `ended` | `end_reason` is `stopped`, `idle`, `cleanup_unconfirmed` or `shutdown`. |

### 4.8 Errors

An error object is `{code, message, detail}`. `message` is one sentence. `detail` is optional. Its fields are named per code below. It MAY include `exit_status`, `signal` and `stderr_tail`: the last 2,000 bytes of the provider's own stderr. The layer MUST NOT add the prompt, the response or environment values to `detail`.

| Code | Channel | When |
| --- | --- | --- |
| `invalid_args` | operation | Missing, unknown or ill-typed parameters, a relative `cwd`, or creation-only parameters with `session_id`. `detail.args` lists the names. |
| `invalid_option` | operation | A `provider`, `effort` or `access` value outside `agent_info`. `detail.option` names it. |
| `session_not_found` | operation | No live or ended session with that id. |
| `session_exists` | operation | `name` was already used in this layer's lifetime. |
| `session_ended` | operation | `agent` with `session_id`, `agent_cancel` or `agent_stop` on an ended session. |
| `invocation_not_found` | operation | No such invocation, or it was evicted. |
| `request_conflict` | operation | `request_id` was used with different parameters (section 5.6). |
| `cwd_missing` | operation when starting; invocation on a later turn | The working directory does not exist (section 5.11). |
| `resume_not_found` | operation | The provider has no session with the `resume` id in that `cwd` (section 5.9). |
| `provider_session_in_use` | operation | The `resume` id is owned by another session in this layer. `detail.owner` names it. |
| `too_many_sessions` | operation | Starting a session would exceed `max_sessions`. |
| `queue_full` | operation | The session already has `max_queued` queued invocations. The running one does not count. |
| `depth_exceeded` | operation | The new session's depth would exceed `max_depth`. |
| `provider_unavailable` | operation when starting; invocation on a later turn | The CLI binary is missing or cannot start. |
| `layer_unavailable` | surface | A surface cannot reach or start the layer (section 6.2). |
| `turn_failed` | invocation | The provider ran and reported failure. `detail.provider` has its report. |
| `provider_exit` | invocation | The CLI exited nonzero, or exited zero without a terminal report. |
| `provider_protocol` | invocation | The wrapper could not parse the provider's output. |
| `cancelled` | invocation | The invocation was cancelled. `detail.by` is `cancel`, `stop`, `idle`, `cleanup_unconfirmed` or `shutdown`. |

"Operation" errors fail the call, and nothing is created or changed. "Invocation" errors appear on an invocation with status `failed` or `cancelled`, and the call that submitted it succeeded.

## 5. Semantics

Each rule names the run or review that led to it.

**5.1 One turn at a time.** A session MUST run at most one turn at a time. Two concurrent turns on one provider conversation would fork it.

**5.2 Session ids.** A session id MUST NOT be reused for the lifetime of the layer process, even after its record is evicted. Reuse fails with `session_exists`. Generated ids MUST NOT collide with any id used before. Two concurrent `agent` calls with the same `name` produce exactly one session; the other call fails with `session_exists`. A caller that wants a stable name across layer restarts uses `resume` (section 5.9).

**5.3 Provider session ownership.** Within one layer, a provider session id (with its provider) has at most one owner at a time. A session owns its provider session id from the moment the id is known until the session ends and its last turn's cleanup is confirmed. Adopting an owned id fails with `provider_session_in_use`. The layer cannot detect use of the same conversation outside itself, such as a person resuming it in a terminal. Callers MUST NOT do that while the layer owns it.

**5.4 Ordering.** Each session has one total order of submissions, cancels, stops and terminal transitions.

- Submissions accepted after a cancel queue normally, in submission order.
- A cancel affects only invocations accepted before it.
- A stop rejects later submissions with `session_ended`.
- Every invocation becomes terminal exactly once. When a turn's completion and a cancel race, the first transition recorded wins, and the other has no effect on that invocation.
- Invocation numbers are never reused.

**5.5 Turns outlive their caller.** A turn runs in the layer, not in the call that submitted it. If the caller disconnects, its wait expires or its process exits, the turn continues and its result is held (runs 5 and 6).

**5.6 Idempotent submission.** With `request_id`, a submission that the layer has already accepted with the same `request_id` and the same parameters returns the original invocation instead of a new one. This holds within one session, or across new sessions when there is no `session_id`. The same `request_id` with different parameters fails with `request_conflict`. Keys are kept as long as the invocation is held. Without `request_id`, a caller that loses a response cannot know whether the prompt was accepted. It MUST check with `agent_result` or `agent_sessions` before resending.

**5.7 Waiting.** `wait_ms` bounds how long a call blocks waiting for its invocation to become terminal. This applies whether the invocation is queued or running. When the wait expires, the call returns the invocation as it stands, and nothing else changes. When an invocation becomes terminal for any reason, including cancel, stop or eviction of other records, every waiter on it returns at once. A surface with a lower cap clamps `wait_ms` to that cap and does not reject the call (section 6.1). Waiting is the design. Polling with short waits is a fallback (run 1: seven polls for one turn).

**5.8 Creation-only options.** The options marked creation-only in section 4.1 are fixed when the session starts. Passing them with `session_id` MUST fail rather than be ignored. A caller who wants different options starts another session.

**5.9 Adopting a provider session.** With `resume`, a new session continues an existing provider conversation: a Claude session id or a Codex thread id. This is how a session survives a layer restart, and how a caller picks up a session started anywhere else.

- Before accepting the call, the layer MUST check through the wrapper (W12) that the provider has that session for that `cwd`. Claude stores sessions by project directory, so a Claude session from another directory is not found. If it is not found, the call fails with `resume_not_found`.
- The adopted session's `usage_total` starts empty. Its first turn's usage follows section 5.15.

**5.10 Access.** `access` is fixed for the session's life and MUST apply on every turn, including resumed ones (run 6: codex_wrapper dropped the sandbox on resumed turns until #142).

| Value | Claude | Codex |
| --- | --- | --- |
| `inherit` (default) | No permission-mode or tool flags. The CLI applies the user's settings. | No sandbox flag. The user's configuration applies, and the layer turns approval prompts off, because a headless turn cannot answer them. |
| `read_only` | Only tools that read files. No tool that writes files or runs commands. No approval prompts. | Read-only sandbox, approval prompts off. |
| `workspace_write` | not offered | Workspace-write sandbox, approval prompts off. |
| A Claude permission mode (`plan`, `accept_edits`, `auto`, `dont_ask`, `bypass_permissions`) | That mode. | not offered |

- `inherit` means the user's provider configuration as it is when each turn starts. The layer does not snapshot it, so a change to the user's configuration affects later turns. The narrowing values do not depend on user configuration.
- `inherit` is not the caller's mode. The layer cannot see the caller's mode. A caller that wants a child to match its own mode passes that mode explicitly. Under Claude settings that allow no shell commands, `inherit` gives a headless session that cannot run commands (runs 3 and 6).
- An omitted `access` is always `inherit`. No hook, surface or other configuration changes that default.

**5.11 Working directory.** `cwd` MUST be an absolute path. The layer stores it as given and does not resolve symlinks. It MUST exist when the session starts, or the call fails with `cwd_missing`. Before each turn the layer MUST check it again. If it is missing, that invocation fails with `cwd_missing`, the CLI is not started, and the session stays open for later prompts (run 6: a session removed its own worktree, and its next turn failed as an opaque exit 2).

**5.12 Cancel and cleanup.** Cancelling a turn MUST stop its whole process tree: the CLI, the tools it started and their descendants.

- When the wrapper confirms that the tree has exited, `cleanup` is `confirmed`.
- When the wrapper has not confirmed it yet, `cleanup` is `pending`, and the session is in state `cleaning`. While a session is `cleaning`, no turn starts on its provider session; new submissions queue.
- When the wrapper confirms exit, the session returns to `idle` or starts its next queued turn.
- If `cleanup_ms` passes without confirmation, the session ends with `end_reason: cleanup_unconfirmed`, and its queued invocations are cancelled with `detail.by: cleanup_unconfirmed`. Its provider session id stays owned by the ended record (section 5.3) until the record is evicted.
- The same rules apply when a turn ends normally while descendants are still running, and to `agent_stop` and shutdown.

**5.13 Ended sessions and retention.** A session ends when it is stopped (`stopped`), idle past `idle_ms` (`idle`), unable to confirm cleanup (`cleanup_unconfirmed`), or ended by layer shutdown (`shutdown`).

- An ended session keeps its session object and its held invocations, with their full results, until the record is evicted. `agent_result` and `agent_sessions` with `include_ended` work on it. Nothing else does.
- Ended records are bounded by `max_ended`, oldest `ended_at` evicted first. Each session's held invocations are bounded by `max_results`, oldest terminal invocation evicted first. Pending invocations are never evicted.
- A turn failure does not end a session. The session stays open and runs its next queued invocation.
- `idle_ms` defaults to 24 hours, and 0 disables it. An idle session has no running or queued invocation and no activity for `idle_ms`. Without the limit, orphaned children would fill `max_sessions` for the life of the layer.

Run 6 is the reason for keeping results after a stop: two reviewer sessions that another agent started and stopped left no trace.

**5.14 Nesting and callers.** A session can call the layer to start sessions of its own (run 6, recursive). The layer MUST make this work with no configuration in the child, over every surface.

- Each turn's environment carries these variables, and their names are normative:

  | Variable | Value |
  | --- | --- |
  | `AGENT_SESSION_LAYER` | The layer's address (section 6.2). |
  | `AGENT_SESSION_TOKEN` | The layer's access token (section 6.2). |
  | `AGENT_SESSION_ID` | This session's id. |
  | `AGENT_SESSION_DEPTH` | This session's depth. |

- A surface started in an environment with `AGENT_SESSION_LAYER` MUST connect to that layer.
- When a caller is a session, the surface sets `parent_session_id` from `AGENT_SESSION_ID` unless the caller passes one. An explicit `parent_session_id` MUST name a session in this layer, live or ended, or the call fails with `session_not_found`.
- The layer derives depth from the parent's record. A new session at a depth above `max_depth` fails with `depth_exceeded`.
- Stopping, ending or evicting a parent does not affect its children. Children keep their `parent_session_id` and depth.
- `caller_id` is opaque metadata that a surface or caller supplies, for example a host conversation id. The layer stores it and filters on it, and attaches no other meaning to it.

**5.15 Usage per turn.** `usage` on an invocation MUST cover that turn alone.

- If the provider reports per-turn counters, they pass through unchanged.
- If the provider reports a running total for the conversation (Codex reports `turn.completed.usage` as the thread's total, including on resumed turns), the layer subtracts the previous total. Only consecutive observations count. A turn whose total is missing clears the baseline. A counter that decreases resets the baseline to the new value. A turn with no valid baseline reports no usage. That includes the first turn of an adopted session with such a provider.
- `usage_total` is the sum of the per-turn values the layer reported.

**5.16 No turn limit.** The layer MUST NOT impose a turn duration limit by default. Native subagents have none, and a 10-minute default ended a whole-issue turn (run 5). A wrapper's idle and whole-run timeouts MUST be off unless the operator configures them.

**5.17 Child environment.** The CLI's environment is the layer's environment with these changes, applied in order:

1. Remove the variables on the layer's strip list. The list has two parts, both of which the implementation MUST document:
   - **Built-in entries.** Variables that mark the layer's own runtime, such as an application release's boot variables and the `PATH` entries they add (codex_wrapper #156). Variables that mark the layer's parent process as an agent session, by exact name. Build-tool switches that change tool output for the agent (run 6: `MIX_QUIET`).
   - **The operator's entries.**
2. Set the variables in section 5.14.
3. Apply the operator's trusted overrides. Callers cannot set environment variables.

- The strip list MUST name variables exactly, or by a prefix together with the exact variables the prefix excludes. Credentials and provider routing variables MUST pass through unchanged. For example, `CLAUDE_CODE_OAUTH_TOKEN` and `CLAUDE_CODE_USE_BEDROCK` share a prefix with Claude Code's session markers and must not be removed with them.
- Environment values are never copied into results, records or logs.

**5.18 Content in logs.** The layer MUST NOT write prompts, response text or environment values to logs or telemetry. Logs and telemetry carry ids, statuses, timestamps, durations, usage and error codes. Held results are the only place response text is kept. They live in the layer's memory or store, within the bounds of section 5.13.

**5.19 Restart and shutdown.**

- **Graceful shutdown.** On a graceful shutdown the layer cancels every running and queued invocation (`detail.by: shutdown`), applies the cleanup rules of section 5.12, and ends every session with `end_reason: shutdown`.
- **Crash.** A crashed layer cannot clean up. CLIs it started may still be running, so a caller MUST NOT resume a provider session from a crashed layer until those processes have exited.
- **No resend.** A turn interrupted by a restart is never resent automatically.
- **Recovery.** Provider sessions survive a restart. A caller recovers with `agent` and `resume`, using the `provider_session_id` it saw. The layer reports that id while the first turn runs (W2), so an interrupted first turn stays recoverable.
- **Persistence.** The layer is not required to persist sessions or records across a restart (section 11).

## 6. Surfaces

### 6.1 Equivalence

Every surface exposes the six operations of section 4 with the same parameters, types, defaults, results and error codes. Only the names change, following the surface's conventions:

| Operation | MCP tool | CLI command |
| --- | --- | --- |
| `agent` | `agent` | `agent` |
| `agent_result` | `agent_result` | `agent-result` |
| `agent_cancel` | `agent_cancel` | `agent-cancel` |
| `agent_stop` | `agent_stop` | `agent-stop` |
| `agent_sessions` | `agent_sessions` | `agent-sessions` |
| `agent_info` | `agent_info` | `agent-info` |

A surface MAY lower the `wait_ms` cap. It reports the cap in `agent_info.surface`, advertises it in its schema or help, and clamps larger values to it. A surface MUST NOT add semantics: everything in section 5 holds whichever surface the caller uses.

### 6.2 The layer and how surfaces reach it

- There is one layer per user per machine. It listens only on a local endpoint that other users cannot reach: a Unix domain socket in a directory only the user can read, or a loopback address.
- The layer writes an address file with its endpoint, its token and its spec version. The file sits at a documented per-user path and is readable only by the user.
- Every request carries the token. A request without a valid token is rejected.
- A surface finds the layer from the environment first (`AGENT_SESSION_LAYER` and `AGENT_SESSION_TOKEN`), and otherwise from the address file.
- If no layer is reachable, the MCP surface MAY start one in the background, wait for its address file, and connect to it. The CLI MUST NOT start one implicitly; it fails with `layer_unavailable` and names the command that starts one.
- A layer the MCP surface starts outlives that MCP server process. Sessions belong to the layer, so they outlive every client (section 5.5).

### 6.3 MCP

- The MCP surface offers one tool per operation. The input schema is the operation's parameter table as JSON Schema, with `additionalProperties: false`.
- The result is the operation's JSON result as structured content, plus a short text rendering. An operation error is a tool error that carries the error object.
- The MCP surface may run over stdio, started by the host, or as a local HTTP endpoint. Either way it is a client of the layer in section 6.2. It holds no sessions itself.

### 6.4 CLI

- Commands are named as in section 6.1. Parameters are long options, with underscores written as hyphens (`--session-id`, `--wait-ms`). Booleans are flags.
- Any string parameter accepts `@path`, which reads the value from the file at `path`, resolved against the CLI's working directory. `@-` reads stdin, and at most one parameter may use it. `@@` at the start writes a literal `@`.
  - Files are read as UTF-8, trailing newlines included, and expanded once. A file that cannot be read fails with `invalid_args`.
  - MCP strings are always literal.
  - The reason: in run 6 a prompt built in an unquoted shell heredoc lost three phrases to command substitution.
- The CLI writes the JSON result to stdout. Its exit status:
  - 0 when the operation succeeds, including when it returns a `failed` invocation;
  - 1 for an operation error, with the error object on stderr;
  - 2 for `layer_unavailable`.
- `serve` starts a layer in the foreground. `init` installs the host-integration profile when the implementation offers it (section 7).
- With a reachable layer, `agent-info` and `agent-sessions` MUST finish within 300 ms at the 95th percentile on the reference machine. Parallel CLI invocations MUST NOT serialize on a shared lock (run 6: Mix build-lock contention).

## 7. Host-integration profile (optional)

An implementation MAY offer this profile. If it does, the profile MUST meet this section and H1 in section 9. Nothing in sections 4 to 6 depends on it, and the operations behave the same without it. Host facts below come from the plugins and hooks cookbook, reviewed 2026-10-28 against Claude Code 2.1.312 and Codex CLI 0.163.0. Re-check them on each host release.

**7.1 Plugin.** `init` installs one plugin for both hosts through each host's marketplace commands, never by editing host settings directly. The plugin carries:

- the MCP surface's server configuration, in each host's format;
- the CLI, where the host can put it on the agent's `PATH`;
- the skill (7.2);
- the hooks (7.3).

- On hosts that review hooks before running them, `init` MUST tell the user to review them. Codex trusts each hook by its hash, so a changed hook needs review again.
- Plugin state lives in the host's plugin data directory, not the plugin root.
- Surfaces that reject plugins carrying executables get the MCP server only.

**7.2 Skill.** One skill teaches when to use the operations instead of the host's native subagent tool:

- for work that must outlive the conversation;
- for a counterpart on the other provider;
- for a session that another agent will pick up.

It also teaches the three patterns in C1 to C3, how to pass the caller's own mode as `access`, and what to do when the plugin's hooks are disabled. It contains instructions only.

**7.3 Hooks.** Each hook is advisory. It reads the layer through the operations, using the `caller_id` filter of `agent_sessions` and the `delivered` field on invocations. It makes no network calls outside the local layer. When the layer is unreachable it fails open with a short message.

| Hook | Host event | Behaviour |
| --- | --- | --- |
| Caller id | Session start | Hook input carries the host session id. The surface uses it as `caller_id` on sessions this caller starts. |
| Completion notice | Claude Code: a monitor or a background hook that can wake the session. Codex: a background hook, delivered at the next safe point. | Tells the caller when one of its invocations has become terminal and is not yet `delivered`. Codex does not wake an idle session, so the notice can be late. |
| Brief | Session start, including resume and after compaction | A factual list of the caller's live and recently ended sessions and its pending or undelivered invocations, under 1,500 characters. |
| Check once at the end | `Stop`, honouring `stop_hook_active` | If the caller has terminal invocations with `delivered: false`, block once and name them. |

- No hook changes an operation's defaults (section 5.10).
- Child sessions MUST NOT depend on a `SessionEnd` hook for cleanup. Hosts give it 1 to 3 seconds, and a child outlives its caller by design.
- Under `inherit`, a child session loads the user's own hooks, plugins and instructions. The variables in section 5.14 let those hooks tell a headless child from an interactive session.

## 8. Wrapper contract

What the layer needs from a provider wrapper, stated as capabilities. A wrapper may be a library in the layer's language or a process the layer calls. Appendix A maps the current Elixir wrappers.

| Id | Capability | Needed by |
| --- | --- | --- |
| W1 | Run one turn non-interactively, fresh or resuming a provider session id, in a given working directory. Return a terminal outcome: success or failure, final message, provider session id, usage as reported, cost when reported. Success means the provider reported success and the process exited 0. | 4.1 |
| W2 | Report the provider session id as soon as the provider emits it, before the turn ends. | 4.7, 5.3, 5.19 |
| W3 | Apply the same model, effort and access options on fresh and resumed turns. | 5.8, 5.10 |
| W4 | Express `inherit` as in section 5.10: no permission flags, with Codex approval prompts off. Express each narrowing value. | 5.10 |
| W5 | Stop a running turn's whole process tree, and confirm when the tree has exited, also after a turn that ended normally. | 5.12 |
| W6 | Set and unset child environment variables per turn, with unsets honoured on every spawn path. | 5.14, 5.17 |
| W7 | Deliver the prompt without an argv size limit (stdin or a file), and keep it out of the process table. | 4.1, 5.18 |
| W8 | Impose no turn timeout unless configured. | 5.16 |
| W9 | Report each failure distinctly with its detail (exit status, signal, stderr tail): missing binary or spawn failure, provider-reported failure, nonzero exit or exit zero without a terminal report, unparseable output. | 4.8 |
| W10 | Report usage as per-turn counters, or as running totals with that stated, so the layer can apply 5.15. | 5.15 |
| W11 | Report whether the provider reports cost. | 4.7 |
| W12 | Check whether a provider session id exists for a working directory, without running a turn. | 5.9 |

Optional: W13, steer or interrupt a turn without ending it. The current operations do not use it (section 11).

A wrapper gap MUST be fixed in the wrapper, not worked around in the layer. Run 6 found two such gaps, codex_wrapper #142 and claude_wrapper #338. Both were already fixed upstream. Both had been hidden by logic that the GenAgent adapters carried themselves.

## 9. Conformance

An implementation conforms when it passes C1 to C18, against fake CLIs in automated tests, and C1 to C5 against the real CLIs in a live smoke run. A fake CLI is a test executable that records its argv, environment and stdin, and emits provider-shaped output on cue.

| Id | Scenario | Checks |
| --- | --- | --- |
| C1 | Single-use: one `agent` call with a whole task, `agent_result` until terminal, `agent_stop`. | Terminal result. The ended record is readable. No descendant process of the session remains. |
| C2 | Counterpart: one session, three turns, plus two follow-ups submitted while the second turn runs. | The same provider session id on every turn. The invocations run in submission order. Per-turn usage on each. |
| C3 | Recursive: a session starts a child session through the MCP surface and through the CLI, with no configuration, using the variables in 5.14. The child runs two turns and is stopped by its parent. | The child's `parent_session_id` and depth. Both children are visible in the same layer and listed with `include_ended`. |
| C4 | Restart: during a running first turn, after its `provider_session_id` is reported, shut the layer down gracefully. Start a new layer and call `agent` with `resume`. | The interrupted invocation is `cancelled` with `detail.by: shutdown`. The conversation continues. The interrupted prompt is not resent. |
| C5 | Cancel: cancel a turn whose CLI has started a long-running descendant. | Independently of what the layer reports, no descendant remains once `cleanup` is `confirmed`. With a fake wrapper that withholds confirmation, the session is `cleaning`, new turns wait, and after `cleanup_ms` the session ends with `cleanup_unconfirmed`. |
| C6 | Working directory: remove the cwd between turns, then restore it. | `cwd_missing` on that invocation, the CLI not started, and the next turn runs. |
| C7 | Access: a `read_only` session's resumed turn, and an `inherit` session's turns. | The fake CLI's argv carries the narrowing on the resumed turn. `inherit` passes no permission flags. Live, a write attempt in the `read_only` session fails. |
| C8 | Usage: running totals over four turns, with one turn missing its total, then a decrease. | Per-turn values follow 5.15 exactly. |
| C9 | Environment: the layer's environment holds a runtime boot variable, a parent-session marker, an operator strip entry, a credential sharing the marker's prefix, and an unrelated variable. | The child lacks the first three, and has the credential, the unrelated variable and the variables in 5.14. |
| C10 | Surfaces: C1 to C3 through MCP and through the CLI. | Results are identical apart from ids, timestamps, durations, text and usage values. Error codes are identical. |
| C11 | Errors: trigger every operation error code in 4.8. | Each returns its code and creates or changes nothing. |
| C12 | Races: a cancel racing completion; submissions racing a cancel; a stop during a wait; two `agent` calls with the same `name`. | The rules in 5.2, 5.4 and 5.7. |
| C13 | Waits and disconnects: `wait_ms` expiry on queued and running invocations; a caller that disconnects mid-wait. | The pending status is returned at expiry. The turn continues and its result is held. |
| C14 | Retention: exceed `max_results`, `max_ended` and `idle_ms`. | Eviction order. Pending invocations are never evicted. `end_reason: idle`. |
| C15 | Idempotency: resend with the same `request_id`, then with the same key and different parameters. | The original invocation, then `request_conflict`. |
| C16 | Long turn: a fake turn that runs past every wrapper default idle bound, at least 10 minutes. | It completes. |
| C17 | Prompt handling: a prompt over 1 MiB containing a sentinel string. | Not in any process's argv, nor in logs, telemetry or error `detail`. |
| C18 | CLI arguments: `@path`, `@-` and `@@`, and timing of `agent-info` under 8 parallel callers. | Exact values. The bound in 6.4. |
| H1 | Host-integration profile, when offered: `init` on both hosts, then C1 from each host's MCP tools. | Tools listed under the plugin's names. A completion notice reaches the caller by its next turn at the latest. The brief lists the caller's sessions. With the plugin's hooks disabled, C1 still passes. |

## 10. Evaluation of the working hypothesis (not normative)

The hypothesis in section 1 is that a provider wrapper plus a thin layer meets this spec, with no agent framework in between. An implementation supports the hypothesis when:

- **E1.** It conforms (section 9).
- **E2.** Its dependency tree contains no agent framework, meaning a library whose purpose is to model agents, their callbacks or their orchestration. For this ecosystem that means GenAgent, GenAgent Ensemble and the GenAgent backend adapters. Process, transport, serialization, telemetry and surface libraries are expected.
- **E3.** Every wrapper capability in section 8 is met by the wrapper itself. Any capability the layer had to work around counts against the hypothesis until the wrapper is fixed.
- **E4.** The three run 6 patterns, run live through it, produce results comparable to run 6.

## 11. Open questions

1. **Streaming.** Should `agent_result` offer partial output, or a progress summary (last activity, tools used so far), while a turn runs? Native subagents report only at the end. Run 6 never needed more, but a person watching a long turn might.
2. **Steering.** Should a prompt submitted during a turn be able to steer it (W13) rather than queue? Codex's app server and Claude's duplex mode can. That needs a live check, and a decision on whether steering is a parameter of `agent` or a separate operation.
3. **Persistence.** Should sessions and ended records persist across a restart, as dormant handles that resume by provider id on their next prompt, rather than relying on callers to `resume`?
4. **Isolation.** Should the layer offer a worktree per session, as Claude Code's subagent `isolation: worktree` does, or leave it to prompts as in runs 5 and 6?
5. **Messages without a turn.** Codex's `send_message` delivers text without starting a turn. Is that needed?
6. **Budgets.** Should the layer enforce cost or token budgets per session or across sessions, or leave that to callers?
7. **Native subagent routing.** Should a hook on the host's own subagent tool offer the layer instead? The current answer is no. Rewriting a tool call the model chose is invisible to the model, and the cookbook lists it as an anti-pattern. The skill (7.2) teaches when to choose the layer.
8. **Address file location.** A path under the user's state directory (for example `$XDG_STATE_HOME/<tool>/layer.json`), or the host plugin data directory, or both.

## Appendix A. Mapping to the Elixir wrappers (non-normative)

As of claude_wrapper 0.19.0 and codex_wrapper 0.9.0. Where codex_wrapper main differs, the main state is noted.

| Id | claude_wrapper 0.19.0 | codex_wrapper 0.9.0 (main) |
| --- | --- | --- |
| W1 | Met. `Session.send/3` runs `claude -p`, with `--resume` from the second turn; `Result` has `result`, `session_id`, `cost_usd`, `usage`, `is_error`. | Met. `Session.send/3` runs `exec`, then `exec resume <thread_id>`. Main adds `CodexWrapper.Turn`, whose status treats a nonzero exit as failure even after `turn.completed`. |
| W2 | Partial. `Query.execute/3` takes a `:session_observer` that reports the id at `system/init`; `Session.send/3` does not expose it. The pending `ClaudeWrapper.Run` (#351) does. | Partial. `thread.started` carries the id; `Session.send/3` reports it only after the turn. |
| W3 | Met. Session query options apply to every turn. | Met since 0.9.0 (#142, #160). |
| W4 | Met: `permission_mode`, `tools`. | Met: `sandbox`, `approval_policy`, `ignore_user_config`. |
| W5 | Partial. The default Port runner signals the CLI when its owner dies, but not its process group. `Runner.Forcola` kills the group, selected by application configuration. `ClaudeWrapper.Run` (#351) adds cancel with recorded evidence, but cleanup is `unknown` with Forcola 0.7. Confirmation of tree exit is the gap. | Partial. The same Port and Forcola split, and no async handle. |
| W6 | Met for set and unset (`false`, #338). Release scrub since #340. Agent-session markers and build-tool switches are not scrubbed; that is the layer's strip list (5.17). | Met for set and unset (#162). Release scrub on main (#170, #174, unreleased). |
| W7 | Met. Prompts go on stdin by default (`prompt_input`). | Met since 0.9.0 (#169). |
| W8 | Met. One-shot runs have no timeout unless `Config.timeout` is set. | Met for `Session.send/3`. Streaming and evidenced paths default to a 300 s idle bound. |
| W9 | Met. `%ClaudeWrapper.Error{}` kinds. | Partial. `{:exit, code, result}` and `{:spawn, reason}`. In run 6 a missing cwd produced exit 2 with empty stderr. |
| W10 | Met. Per invocation. | Partial. The CLI reports running totals, and the wrapper does not say so. On main, `Session.total_usage/1` adds each turn's running total, so it overcounts from the second turn on. #173 builds on it. |
| W11 | Met. | Met: Codex reports no cost. |
| W12 | Gap. No existence check for a session id. | Gap. No existence check for a thread id. |

## Appendix B. The spike against this spec (non-normative)

#140 (`GenAgentServer.Session`, `GenAgentServer.Ops.Agent`) implements `agent`, `agent_result`, `agent_cancel`, `agent_stop` and `agent_sessions`. It has no `resume`, `parent_session_id`, `caller_id`, `request_id`, `include_ended` or `agent_info`. It runs inside gen_agent_server, which is one release per user. Where it differs from this spec:

| Rule | Spike |
| --- | --- |
| 4.7 | `queued` and `running` are both reported as `pending`. No timestamps beyond `duration_ms`. No `delivered`. Uses `null`. |
| 4.8 | Some errors are inspected tuples with code `error`. |
| 5.2, 5.3 | A name can be reused after `agent_stop`. No ownership of provider session ids. |
| 5.9 | No `resume`. |
| 5.11 | The cwd is checked only when the session starts. |
| 5.12 | Cancel kills the turn task. With the Port runner, the CLI's children can survive. No `cleanup` field and no `cleaning` state. |
| 5.13 | `agent_stop` discards everything. No idle limit. |
| 5.14 | The environment carries neither session variables nor the layer address. The recursive run passed the node name and environment through the prompt. |
| 5.15 | Codex usage is passed through as running totals. |
| 5.17 | Release variables are scrubbed by the server's child environment. Agent-session markers and `MIX_QUIET` are not. |
| 6.2 | Reached through release rpc with the Erlang cookie. No address file or token. |
| 6.4 | The CLI is `mix gen_agent_server.ops`, run from a server checkout, without `@path`. |

## Appendix C. Native subagent tools (non-normative)

The operations are shaped after the subagent tools that Claude Code and Codex give their own sessions; see [agent-interface.md](agent-interface.md) for the comparison. The additions over them are:

- a session that outlives the caller's conversation (5.5);
- held results readable from anywhere (4.2);
- adopting provider sessions (5.9);
- ended records (5.13).

As in both native tools, a call has no permission parameter beyond `access`, and there is no turn limit.

## Appendix D. Changes from draft 0.1 (non-normative)

From the two independent reviews of 0.1:

- **Lifecycle.**
  - One order per session (5.4).
  - Ownership of provider session ids (5.3).
  - A `cleaning` state, so no turn starts while an earlier tree may still be alive (5.12).
- **Identity.** Session ids are never reused (5.2). `caller_id` is separate from `parent_session_id` (5.14). `request_id` makes submissions idempotent (5.6).
- **Results.** Ended sessions keep their full results until evicted (5.13). Each error code has one channel, and `cancelled` is an invocation error, not an operation error (4.8). Null is not used.
- **Topology.**
  - One layer per user per machine, with surfaces as its clients (6.2). This replaces "one layer per stdio client", which broke nesting and session lifetime.
  - Normative environment variable names (5.14).
  - A local endpoint with a token.
- **Access.** `inherit` is defined as configuration at each turn. Hooks can no longer change defaults (5.10).
- **Environment.** Exact strip lists replace the BEAM-specific rule, and credentials sharing a prefix pass through (5.17).
- **Host integration.** Moved to an optional profile (7). Its hooks use `caller_id` and `delivered`, which the core now provides.
- **Discovery.** `agent_info` lets callers find providers, efforts, access values and limits (4.6).
- **Conformance.**
  - Scenarios assert observable facts (C5, C7, C10).
  - Every MUST without a scenario now has one (C11 to C18).
  - The dependency check moved out of conformance into an evaluation of the hypothesis (10).

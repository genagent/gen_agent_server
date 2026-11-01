# Agent session spec

Status: draft 0.5, 2026-11-01. Derived from the `agent` spike (#140) and procedure runs 1 to 6. The history and evidence are in [agent-interface.md](agent-interface.md) and in the run records on the `docs/issue-process` branch (#134). Drafts 0.1 to 0.4 were each reviewed by one Claude and one Codex session; Appendix D lists what changed.

Sections 1 to 9 are normative, except where a section says otherwise. Section 10 and the appendices are not normative. The spec assumes a POSIX host: process groups, signals and per-user file permissions.

## 1. Goal

This spec defines one interface for creating, resuming and driving headless Claude Code and Codex sessions, for any task and any caller. A caller can be a person at a terminal or another agent, including one started through this same interface. A session may serve a single task and end, or stay open as a long-running counterpart across many turns and conversations. The spec defines the operations and their semantics. It defines two surfaces over the same operations: MCP tools for agents and a CLI for people. It also defines the contract the layer needs from a provider wrapper, the library that runs one CLI turn and carries its session id. The spec is independent of language and runtime. Its working hypothesis is that a provider wrapper plus a thin session layer meets it, with no agent framework in between. The conformance scenarios and the evaluation in section 10 test that hypothesis, and the implementation stack is chosen from what the spec requires. The behaviour of the existing spike, and the evidence from the procedure runs, are the starting guideline.

## 2. Scope

In:

- Start a session, continue it, adopt an existing provider session, cancel a turn, stop a session, list sessions, describe the layer.
- Hold results so a caller can collect them later, from any conversation.
- One long-lived layer per user per machine, reached by every surface over one defined protocol (section 6.2), so layers, surfaces and children from independent implementations interoperate.
- Process and environment hygiene for the CLIs the layer starts.
- The capabilities the layer needs from each provider wrapper.
- An optional host-integration profile: a plugin, a skill and hooks for Claude Code and Codex (section 7).

Out (the caller's job or another layer's):

- Orchestration: pipelines, voting, review loops, routing between providers, scheduling. Run 6 built all three of its patterns from these operations without help from the layer.
- Worktrees, branches and pull requests. The prompt or the caller owns them (runs 5 and 6).
- Reading provider session archives, summaries, search.
- Approvals and permission prompts during a turn. Access is fixed when a session starts (section 5.10).
- Partial response text while a turn runs. A running invocation reports progress without content (section 4.7).
- Worktrees or other workspace isolation. In runs 5 and 6 the agents created their own worktrees from the prompt. A layer that owned them would take on git, repository layout, branch naming and cleanup, which the host does for Claude Code's `isolation: worktree` but this layer cannot. `cwd` is the interface.
- Messages that do not start a turn, such as Codex's `send_message`. Such a message waits for the next turn, so a caller gets the same effect by adding it to its next prompt. Mailboxes between agents are orchestration.
- Enforcing cost or token budgets. The layer reports usage per turn, per session and per session tree (section 4.7). `max_depth` and `max_sessions` bound runaway nesting. Stopping work on a budget is the caller's decision.
- Routing the host's native subagent tool to the layer. Rewriting a tool call the model chose is invisible to the model, and the plugins and hooks cookbook lists it as an anti-pattern. The skill (section 7.2) teaches when to choose the layer.
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
| `parent_session_id` | string | from the environment, when starting | Section 5.14. |
| `caller_id` | string | | Section 5.14. |
| `request_id` | string | | Idempotency key (section 5.6). Callers SHOULD use random values. |
| `wait_ms` | integer, 0 to 600000 | 0 | Wait this long for the submitted invocation to end. |

`name`, `resume`, `cwd`, `provider`, `model`, `effort`, `access`, `parent_session_id` and `caller_id` apply only when starting a session. Passing any of them with `session_id` MUST fail with `invalid_args` naming them (section 5.8).

Result: the submitted invocation (section 4.7).

### 4.2 `agent_result`

| Parameter | Type | Default |
| --- | --- | --- |
| `session_id` | string, required | |
| `invocation_id` | string | the session's latest invocation |
| `wait_ms` | integer, 0 to 600000 | 0 |

"Latest" is the invocation with the highest `n`, whatever its status, resolved once when the call is accepted. Result: the invocation. Reading a result does not consume it. The same id returns the same terminal result until it is evicted (section 5.13). Works on live and ended sessions. An `invocation_id` whose session part differs from `session_id` fails with `invocation_not_found`.

### 4.3 `agent_cancel`

| Parameter | Type |
| --- | --- |
| `session_id`, required | string |

Cancels the running turn and every queued invocation accepted before this call (section 5.4). The session stays open. Result: `{session_id, cancelled: [invocation_id], cleanup}`. `cancelled` lists only the invocations this call moved to `cancelled`. `cleanup` is `none` only if no turn was running and no cleanup was outstanding when the call was accepted. Otherwise it is `confirmed` or `pending` according to the wrapper's cleanup evidence (section 5.12).

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

Result: `{sessions: [session]}`, sorted by session id. The filters are combined with AND. Each session carries `invocations`: a summary `{invocation_id, status, delivered}` for each held invocation, oldest first. Listing does not change `delivered`.

### 4.6 `agent_info`

No parameters. Result:

```json
{
  "spec_version": "0.5",
  "layer_version": "...",
  "layer_instance_id": "01J...",
  "started_inside_agent_session": false,
  "providers": [
    {"name": "claude", "efforts": ["low", "medium", "high", "xhigh", "max"], "access": ["inherit", "read_only", "plan", "accept_edits", "auto", "dont_ask", "bypass_permissions"], "available": true},
    {"name": "codex", "efforts": ["low", "medium", "high"], "access": ["inherit", "read_only", "workspace_write"], "available": true}
  ],
  "default_provider": "codex",
  "limits": {"max_sessions": 32, "max_queued": 16, "max_results": 100, "max_ended": 100, "max_depth": 3, "idle_ms": 86400000, "cleanup_ms": 30000},
  "surface": {"name": "mcp", "max_wait_ms": 600000}
}
```

The values shown are examples. `layer_instance_id` is unique per layer process; session ids are unique within it (section 5.2). `available` is false when the CLI binary is missing. `started_inside_agent_session` is true when the layer's own environment held a parent-session marker at start (section 5.17). `surface` describes the surface answering the call. The values MUST match what the layer accepts: a value listed here is never rejected with `invalid_option`, and an unlisted one always is.

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
| `progress` | while `running`, when the wrapper supports W14 | `{last_activity_at, events, last_event_kind, tools_used}`: when the provider last emitted anything, how many events it has emitted this turn, the kind of the last one (`message`, `tool_call`, `tool_result`, `reasoning` or `other`), and the distinct tool names used so far. It carries no text, arguments or results. |
| `text` | when `completed` | The provider's final message. Possibly empty. |
| `usage` | when known | Object of non-negative integers, this turn only (section 5.15). Counter names: `input_tokens`, `output_tokens`, `cached_input_tokens` (cache reads), `cache_write_input_tokens` (cache writes), `reasoning_output_tokens`. A counter the provider does not report is absent. `input_tokens` excludes `cached_input_tokens` and `cache_write_input_tokens`. `output_tokens` includes `reasoning_output_tokens`. The layer converts provider counts to these meanings before computing the differences in 5.15. |
| `cost_usd` | when the provider reports cost | This turn only. |
| `error` | when `failed` or `cancelled` | An error object (section 4.8). |
| `delivered` | always | Boolean. Set to true when the layer returns this invocation in a terminal state from `agent` or `agent_result`, before the response is serialized, so the response that delivers it already shows true. It records an attempted return, not acknowledged receipt. Summaries in `agent_sessions` do not set it. |

**Session.**

| Field | Presence | Meaning |
| --- | --- | --- |
| `session_id`, `provider`, `cwd`, `access`, `depth`, `created_at` | always | |
| `state` | always | `idle`, `running`, `cleaning` (section 5.12) or `ended` (section 4.9). |
| `provider_session_id` | once known | |
| `model`, `effort` | when given at creation | |
| `parent_session_id`, `caller_id` | when set | |
| `cwd_exists` | always on live sessions | Checked when the session is described. |
| `last_activity_at` | always | Last submission or terminal transition. |
| `running` | while a turn runs | Its invocation id. |
| `queued` | always | Invocations queued now. |
| `completed`, `failed`, `cancelled` | always | Counts over the session's life, including evicted invocations. |
| `latest` | once an invocation exists | |
| `usage_total` | when any turn reported usage | Sum of per-turn usage. |
| `cost_usd_total` | when any turn reported cost | |
| `tree_usage_total`, `tree_cost_usd_total` | when any turn in the tree reported usage or cost | The session's totals plus those of every descendant session, live or ended, that the layer still holds. |
| `ended_at`, `end_reason` | when `ended` | `end_reason` is `stopped`, `idle`, `cleanup_unconfirmed` or `shutdown`. A live session that survives a restart is not ended (section 5.20). |

### 4.8 Errors

An error object is `{code, message, detail}`. `message` is one sentence. `detail` is an object. The fields the table names for a code are required; others are optional. `detail` MAY include `exit_status`, `signal` and `stderr_tail`, the last 2,000 bytes of the provider's stderr. Provider diagnostics are held to the same content rule as the layer's own: `detail` MUST NOT contain the response, environment values, or any 32-byte or longer substring of the prompt, and the layer replaces such a span in `stderr_tail` with `[prompt]`.

| Code | Channel | When |
| --- | --- | --- |
| `invalid_args` | operation | Missing, unknown or ill-typed parameters, a relative `cwd`, or creation-only parameters with `session_id`. `detail.args` lists the names. |
| `invalid_option` | operation | A `provider`, `effort` or `access` value outside `agent_info`. `detail.option` names it. |
| `session_not_found` | operation | No live or ended session with that id. `detail.layer_instance_id` names this layer, so a caller can tell a restart from a typo. |
| `session_exists` | operation | `name` was already used in this layer's lifetime. |
| `session_ended` | operation | `agent` with `session_id`, `agent_cancel` or `agent_stop` on an ended session. |
| `invocation_not_found` | operation | No such invocation, or it was evicted. |
| `request_conflict` | operation | `request_id` was used with different parameters (section 5.6). |
| `cwd_missing` | operation at acceptance of a new session; invocation when checked before a turn | The working directory does not exist (section 5.11). |
| `resume_not_found` | operation | The provider has no session with the `resume` id in that `cwd` (section 5.9). |
| `provider_session_in_use` | operation | The `resume` id is owned in this layer. `detail.owner` names the owning session id, or is `recovery` when the owner is a recovery record from an earlier layer instance. |
| `too_many_sessions` | operation | Starting a session would exceed `max_sessions`. |
| `queue_full` | operation | The session already has `max_queued` queued invocations. The running one does not count. |
| `depth_exceeded` | operation | The new session's depth would exceed `max_depth`. |
| `provider_unavailable` | operation when the binary is missing or not executable at acceptance; invocation when a spawn fails after acceptance | The CLI cannot start. |
| `layer_unavailable` | surface | A surface cannot reach or start the layer, or the layer's `spec_version` is incompatible (section 6.2). |
| `unauthorized` | surface | A request reached the layer without a valid token (section 6.2). |
| `turn_failed` | invocation | The provider ran and reported failure. `detail.provider` has its report. |
| `provider_exit` | invocation | The CLI exited nonzero without a provider failure report, including after a success report, or exited zero without any terminal report. |
| `provider_protocol` | invocation | The wrapper could not parse the provider's output. |
| `cancelled` | invocation | The invocation was cancelled. `detail.by` is `cancel`, `stop`, `idle`, `cleanup_unconfirmed` or `shutdown`. |

"Operation" errors fail the call, and nothing is created or changed. "Invocation" errors appear on an invocation with status `failed` or `cancelled`, and the call that submitted it succeeded. A failure the layer detects before accepting a call is an operation error; one it detects after acceptance, including on a session's first turn, is an invocation error.

A turn's outcome is decided in this order: a valid provider failure report gives `turn_failed`; a provider success report with exit status 0 gives `completed`; output the wrapper cannot parse gives `provider_protocol`; anything else gives `provider_exit`.

### 4.9 Session states

| State | `agent` with `session_id` | `agent_cancel` | `agent_stop` | Turn ends | Cleanup confirmed | `cleanup_ms` passes |
| --- | --- | --- | --- | --- | --- | --- |
| `idle` | starts a turn | `cleanup: none` | `ended`, `stopped` | | | |
| `running` | queues | cancels; `cleaning` | cancels; `ended`, `stopped`, cleanup continues | descendants stopped (5.12); `cleaning` | | |
| `cleaning` | queues | cancels queued; `cleanup: pending`, deadline unchanged | cancels queued; `ended`, `stopped`, cleanup continues | | `idle`, or next queued turn | `ended`, `cleanup_unconfirmed`, queued cancelled |
| `ended` | `session_ended` | `session_ended` | `session_ended` | | ownership released | ownership kept |

An ended session never returns to another state. Idle expiry (`idle_ms`) applies only in `idle`. Shutdown cancels every running and queued invocation with `detail.by: shutdown`. Sessions are not ended: they come back `idle` after a restart (section 5.20).

## 5. Semantics

Each rule names the run or review that led to it.

**5.1 One turn at a time.** A session MUST run at most one turn at a time. Two concurrent turns on one provider conversation would fork it.

**5.2 Session ids.** A session id MUST NOT be reused for the lifetime of the layer process, even after its record is evicted. Reuse fails with `session_exists`. Generated ids MUST NOT collide with any id used before. Two concurrent `agent` calls with the same `name` produce exactly one session; the other call fails with `session_exists`. A session keeps its id across layer restarts (section 5.20). `resume` is for adopting provider sessions the layer did not start. Because sessions persist (section 5.20), ids stay unique across restarts of the same layer state directory. `layer_instance_id` identifies the process, not the namespace. The set of used ids grows with the state directory's life; it holds names only.

**5.3 Provider session ownership.** Within one layer, a provider session id (with its provider) has at most one owner at a time. A session owns its provider session id from the moment the id is known until the session has ended and its last turn's cleanup is confirmed. Ownership is kept independently of session records: eviction never releases it, and it survives a layer restart through the recovery records of section 5.12. Adopting an owned id fails with `provider_session_in_use`. The layer cannot detect use of the same conversation outside itself, such as a person resuming it in a terminal. Callers MUST NOT do that while the layer owns it.

**5.4 Ordering.** Each session has one total order of submissions, cancels, stops and terminal transitions.

- Submissions accepted after a cancel queue normally, in submission order.
- A cancel affects only invocations accepted before it.
- A stop rejects later submissions with `session_ended`.
- Every invocation becomes terminal exactly once. When a turn's completion and a cancel race, the first transition recorded wins, and the other has no effect on that invocation.
- Invocation numbers are never reused.

**5.5 Turns outlive their caller.** A turn runs in the layer, not in the call that submitted it. If the caller disconnects, its wait expires or its process exits, the turn continues and its result is held (runs 5 and 6).

**5.6 Idempotent submission.** With `request_id`, a call matching an earlier accepted call returns the earlier invocation instead of submitting again.

- Keys are scoped to the target session when `session_id` is given, and to the layer otherwise.
- The lookup is atomic and runs before every other admission check, including `name` uniqueness and `session_ended`. So two concurrent identical calls produce one invocation, and a retry after a stop still returns the original.
- Calls match when every parameter except `request_id` and `wait_ms` is equal, comparing parameters as given, not as defaulted. A key reused with different parameters fails with `request_conflict`.
- The guarantee lasts while the invocation is held; eviction ends it.

Without `request_id`, a caller that loses a response cannot know whether the prompt was accepted, and MUST check with `agent_result` or `agent_sessions` before resending.

**5.7 Waiting.** `wait_ms` bounds how long a call blocks waiting for its invocation to become terminal. This applies whether the invocation is queued or running. When the wait expires, the call returns the invocation as it stands, and nothing else changes. When an invocation becomes terminal for any reason, including cancel, stop, idle end or shutdown, every waiter on it returns at once. A surface with a lower cap clamps `wait_ms` to that cap and does not reject the call (section 6.1). Waiting is the design. Polling with short waits is a fallback (run 1: seven polls for one turn).

**5.8 Creation-only options.** The options marked creation-only in section 4.1 are fixed when the session starts. Passing them with `session_id` MUST fail rather than be ignored. A caller who wants different options starts another session.

**5.9 Adopting a provider session.** With `resume`, a new session continues an existing provider conversation: a Claude session id or a Codex thread id. This is how a session survives a layer restart, and how a caller picks up a session started anywhere else.

- Before accepting the call, the layer MUST check through the wrapper (W12) that the provider has that session. Claude stores sessions by project directory, so the check uses `cwd`, and a Claude session from another directory is not found. Codex threads are not tied to a directory, so the check ignores `cwd`, and resumed turns run in the new `cwd`. If it is not found, the call fails with `resume_not_found`.
- The adopted session's `usage_total` starts empty. Its first turn's usage follows section 5.15.

**5.10 Access.** `access` is fixed for the session's life and MUST apply on every turn, including resumed ones (run 6: codex_wrapper dropped the sandbox on resumed turns until #142).

| Value | Claude | Codex |
| --- | --- | --- |
| `inherit` (default) | No permission-mode or tool flags. The CLI applies the user's settings. | No sandbox flag. The user's configuration applies, and the layer turns approval prompts off, because a headless turn cannot answer them. |
| `read_only` | Only file read and search tools. No tool that writes files, runs commands, or reaches the network, the web or MCP servers. No approval prompts. | Read-only sandbox, approval prompts off. |
| `workspace_write` | not offered | Workspace-write sandbox, approval prompts off. |
| A Claude permission mode (`plan`, `accept_edits`, `auto`, `dont_ask`, `bypass_permissions`) | That mode. | not offered |

- `inherit` means the user's provider configuration as it is when each turn starts. The layer does not snapshot it, so a change to the user's configuration affects later turns. The narrowing values do not depend on user configuration.
- `inherit` is not the caller's mode. The layer cannot see the caller's mode. A caller that wants a child to match its own mode passes that mode explicitly. Under Claude settings that allow no shell commands, `inherit` gives a headless session that cannot run commands (runs 3 and 6).
- An omitted `access` is always `inherit`. No hook, surface or other configuration changes that default.

**5.11 Working directory.** `cwd` MUST be an absolute path. The layer stores it as given and does not resolve symlinks. It MUST exist when the session starts, or the call fails with `cwd_missing`. Before each turn the layer MUST check it again. If it is missing, that invocation fails with `cwd_missing`, the CLI is not started, and the session stays open for later prompts (run 6: a session removed its own worktree, and its next turn failed as an opaque exit 2).

**5.12 Cancel and cleanup.** Each turn runs in its own process group (W5). Cancelling a turn MUST stop that process group: the CLI, the tools it started and their descendants that stay in the group. A descendant that leaves the group, for example through `setsid`, is outside this guarantee; reparented processes cannot be tracked portably.

- Cleanup is confirmed when every member of the turn's process group has exited. Then `cleanup` is `confirmed`.
- When the wrapper has not confirmed it yet, `cleanup` is `pending`, and the session is in state `cleaning`. While a session is `cleaning`, no turn starts on its provider session; new submissions queue.
- When the wrapper confirms exit, the session returns to `idle` or starts its next queued turn.
- If `cleanup_ms` passes without confirmation, the session ends with `end_reason: cleanup_unconfirmed`, and its queued invocations are cancelled with `detail.by: cleanup_unconfirmed`. Its provider session id stays owned (section 5.3) until cleanup is confirmed, including after the record is evicted. A group that is never confirmed keeps ownership for the life of the layer, and the next layer start handles it.
- When a turn ends normally, the layer stops any members of the turn's process group still running, as for a cancel. Background processes in the group never outlive the turn that started them. The session is `cleaning` until that is confirmed.
- A stop or shutdown closes admission at once and ends the session, while cleanup continues. Confirmation releases ownership and never reopens the session.
- Repeated cancels while `cleaning` return `cleanup: pending` and do not reset the deadline.
- **Recovery records.** For every turn, the layer writes a recovery record to its state directory, and the record is durable before the provider receives the prompt (the prompt goes on stdin, W7, after the record is written). A record holds the group id, the leader's pid and start time, the boot id, the provider and the provider session id once known. The layer makes the provider session id durable in the record before it reports that id in any result. The layer removes the record when cleanup is confirmed.
- **On start.** Before accepting requests, a layer reads the records left by earlier instances:
  - It discards records from an earlier boot.
  - It stops a recorded group only if the group leader is still running with the recorded start time. A numeric group id alone is never enough to signal.
  - It discards the record once the group has exited. Until then, the provider session id in the record stays owned, and adopting it fails with `provider_session_in_use`.
  - If the leader cannot be verified and the group's exit cannot be established, for example because the leader exited while other members remain, cleanup stays unconfirmed. The layer keeps the record and the ownership, and does not signal the numeric group id. It MAY accept requests unrelated to that provider session.

**5.13 Ended sessions and retention.** A session ends when it is stopped (`stopped`), idle past `idle_ms` (`idle`), unable to confirm cleanup (`cleanup_unconfirmed`), or ended by layer shutdown (`shutdown`).

- An ended session keeps its session object and its held invocations, with their full results, until the record is evicted. `agent_result` and `agent_sessions` with `include_ended` work on it. Nothing else does.
- Ended records are bounded by `max_ended`, oldest `ended_at` evicted first. Each session's held invocations are bounded by `max_results`, oldest terminal invocation evicted first. Pending invocations are never evicted.
- A turn failure does not end a session. The session stays open and runs its next queued invocation.
- `idle_ms` defaults to 24 hours, and 0 disables it. It applies only to sessions in state `idle` with no queued invocation and no activity for `idle_ms`. Without the limit, orphaned children would fill `max_sessions` for the life of the layer.

Run 6 is the reason for keeping results after a stop: two reviewer sessions that another agent started and stopped left no trace.

**5.14 Nesting and callers.** A session can call the layer to start sessions of its own (run 6, recursive). For a session whose access permits the tools a surface needs, nesting MUST need no configuration in the child, over every surface that access permits. This does not widen access: a Claude `read_only` session cannot run the CLI or reach MCP servers, and a Codex sandbox that blocks loopback network access cannot reach the endpoint, so neither can nest.

- Each turn's environment carries these variables, and their names are normative:

  | Variable | Value |
  | --- | --- |
  | `AGENT_SESSION_LAYER` | The layer's address (section 6.2). |
  | `AGENT_SESSION_TOKEN` | The layer's access token (section 6.2). |
  | `AGENT_SESSION_ID` | This session's id. |
  | `AGENT_SESSION_DEPTH` | This session's depth. |

- A surface started in an environment with `AGENT_SESSION_LAYER` MUST connect to that layer. If either `AGENT_SESSION_LAYER` or `AGENT_SESSION_TOKEN` is present, both MUST be nonempty. Otherwise the surface fails with `layer_unavailable` and does not fall back to the address file.
- A surface that runs in the caller's environment (the stdio MCP surface and the CLI) sets `parent_session_id` from `AGENT_SESSION_ID`, only on `agent` calls without `session_id`, and only when the caller passes none. A client of the layer's endpoint (section 6.2) passes it explicitly. Explicit and implicit values are validated the same way: they MUST name a session in this layer, live or ended, or the call fails with `session_not_found`.
- The layer derives depth from the parent's record. A new session at a depth above `max_depth` fails with `depth_exceeded`.
- Stopping, ending or evicting a parent does not affect its children. Children keep their `parent_session_id` and depth.
- `caller_id` is opaque metadata that a surface or caller supplies, for example a host conversation id. The layer stores it and filters on it, and attaches no other meaning to it.

**5.15 Usage per turn.** `usage` on an invocation MUST cover that turn alone.

- If the provider reports per-turn counters, the layer converts them as in 4.7 and reports them.
- If the provider reports a running total for the conversation (Codex reports `turn.completed.usage` as the thread's total, including on resumed turns), the layer keeps a baseline per counter and reports the difference.
  - A fresh conversation's baselines start at zero. An adopted conversation's start unknown.
  - A turn whose value for a counter is missing reports no value for that counter and clears its baseline.
  - A turn whose value decreases, or whose baseline is unknown, reports no value for that counter, and its value becomes the baseline.
- `usage_total` is the sum of the per-turn values the layer reported.

**5.16 No turn limit.** The layer MUST NOT impose a turn duration limit by default. Native subagents have none, and a 10-minute default ended a whole-issue turn (run 5). A wrapper's idle and whole-run timeouts MUST be off unless the operator configures them.

**5.17 Child environment.** The CLI's environment is the layer's environment with these changes, applied in order:

1. **Remove parent-session markers.** These are the variables a host agent session sets for the tools it runs. A layer started from inside an agent session would otherwise pass that session's identity, its attended state and its private channels to every child. Run 6 did this: the children got the host's `CLAUDE_CODE_SESSION_ID`, `CLAUDE_CODE_SESSION_ATTENDED`, and the desktop app's `CLAUDE_CODE_MESSAGING_SOCKET` and `CLAUDE_CODE_MESSAGING_TOKEN`. The normative list:
   - `CLAUDECODE`, `CLAUDE_PID`, `CLAUDE_EFFORT`, and every variable starting with `CLAUDE_AGENT_SDK_` or `CLAUDE_CODE_`, except these, which pass through: `CLAUDE_CODE_OAUTH_TOKEN`, `CLAUDE_CODE_USE_BEDROCK`, `CLAUDE_CODE_USE_VERTEX`, `CLAUDE_CODE_SKIP_BEDROCK_AUTH`, `CLAUDE_CODE_SKIP_VERTEX_AUTH`, and any listed in the operator's pass list.
   - `CODEX_THREAD_ID`, `CODEX_SESSION_ID`, `CODEX_SANDBOX`, `CODEX_SANDBOX_NETWORK_DISABLED`.
   - `AGENT_SESSION_LAYER`, `AGENT_SESSION_TOKEN`, `AGENT_SESSION_ID`, `AGENT_SESSION_DEPTH` inherited by the layer itself; step 3 sets them afresh.

   The list reflects Claude Code 2.1.x and codex-cli 0.165 and is versioned with this spec.
2. **Remove the implementation's runtime variables and the operator's strip list.** Runtime variables are those that mark the layer's own runtime, such as an application release's boot variables and the `PATH` entries they add (codex_wrapper #156). Build-tool switches that change tool output for the agent (run 6: `MIX_QUIET`) also count. The implementation MUST document its list. Entries are exact names, or a prefix with the exact names it excludes.
3. **Set the variables in section 5.14.**
4. **Apply the operator's trusted overrides.** Callers cannot set environment variables.

Rules for the steps:

- Steps 1 and 2 MUST NOT remove the pass-through set. That set is exactly `ANTHROPIC_*`, `OPENAI_*`, `CLAUDE_CONFIG_DIR`, `CODEX_HOME`, the exceptions in step 1, and the operator's pass list. Any other variable that step 1 matches is removed.
- The operator's overrides in step 4 MUST NOT replace the four variables of section 5.14.
- Environment values are never copied into results, records or logs.
- A layer SHOULD be started from a login environment, not from inside an agent session. `agent_info.started_inside_agent_session` reports when it was not.

**5.18 Content in logs.** The layer MUST NOT write prompts, response text or environment values to logs or telemetry. Logs and telemetry carry ids, statuses, timestamps, durations, usage and error codes. Held results are the only place response text is kept. They live in the layer's memory or store, within the bounds of section 5.13.

**5.19 Restart and shutdown.**

- **Graceful shutdown.** On a graceful shutdown the layer cancels every running and queued invocation (`detail.by: shutdown`), wakes every waiter, persists every session, and waits up to `cleanup_ms` for cleanup. Process groups still unconfirmed stay recorded for the next start.
- **Crash.** A crashed layer cannot clean up. Before accepting requests, the next layer attempts identity-verified cleanup of every group the crashed one recorded, and restores ownership for every group it cannot confirm (section 5.12). A caller resuming without a new layer start, for example in a terminal, has no such guarantee.
- **No resend.** A turn interrupted by a restart is never resent automatically.
- **Recovery.** Sessions come back after a restart as described in section 5.20. A caller can also adopt any provider session with `agent` and `resume`. The layer reports the provider session id while the first turn runs (W2), so an interrupted first turn stays recoverable either way.

**5.20 Persistence.** The layer persists its sessions in its state directory (section 6.2), with mode 0600 and within the bounds of section 5.13. The store holds the session objects, the held invocations with their full results, the ended records, the idempotency keys of section 5.6, and the set of used ids.

- Each accepted submission and each terminal transition is durable before the layer reports it.
- On start, after recovery (section 5.12), every session that was live comes back `idle`, as a dormant handle. Its next turn resumes its provider session id. It keeps its id, options, parent, counters and held results.
- A session whose provider session id was never reported cannot be resumed. It comes back ended, with `end_reason: shutdown`.
- Invocations that were `running` or `queued` come back `cancelled`, with `detail.by: shutdown`, and are never resent.
- A session whose first turn never reported a provider session id comes back ended.
- Idle expiry counts from `last_activity_at`, including time the layer was down.

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

### 6.2 The layer endpoint and discovery

- **One layer per user per machine.** The layer holds a POSIX `fcntl` write lock covering the whole of `layer.lock`, next to its address file, for the life of the layer process. The file is never removed or replaced. A second layer that cannot take the lock exits, and whoever started it connects to the first.
- **Endpoint.** The layer serves the six operations as an MCP server over Streamable HTTP on a loopback address, at `http://127.0.0.1:<port>/mcp`. Tools, schemas, results and errors are as in section 6.3. Every layer endpoint and surface MUST support MCP protocol version 2025-06-18, and MAY also support later versions negotiated at MCP initialization. This endpoint is the interoperability boundary. Any surface can talk to any conforming layer, and a client that speaks MCP can use the endpoint directly.
- **Token.** Every HTTP request carries `Authorization: Bearer <token>`, including initialization and stream requests. The endpoint rejects a missing or invalid token with HTTP 401 before MCP dispatch, with the body `{"error": <error object with code unauthorized>}`. The stdio MCP surface and the CLI map it to `unauthorized` in their own error forms. Other local users can reach a loopback address, so the token is the barrier. It has at least 128 bits of randomness and is generated at each layer start.
- **Address file.** The layer writes `$XDG_STATE_HOME/agent-session/layer.json`, or `~/.local/state/agent-session/layer.json` when `XDG_STATE_HOME` is unset. The file has mode 0600 and contains `{"endpoint", "token", "spec_version", "layer_instance_id", "pid", "started_at"}`. The layer's state directory, with the process group records of section 5.12, is the same directory.
- **Discovery.** A surface takes the endpoint and token from `AGENT_SESSION_LAYER` and `AGENT_SESSION_TOKEN` when either is present (section 5.14: both must be nonempty, with no fallback). It reads the address file only when neither is present.
  - An address file whose endpoint does not answer, while `layer.lock` is free, is stale.
  - A surface MUST refuse a layer whose `spec_version` differs in major version, or, while the major version is 0, in minor version, with `layer_unavailable`.
- **Starting a layer.** If no layer is reachable, the stdio MCP surface MAY start one in the background, wait for its address file, and connect. The CLI MUST NOT start one implicitly. It fails with `layer_unavailable` and names the command that does. A layer outlives whatever started it, so sessions outlive every client (section 5.5).

### 6.3 MCP

- The MCP surface offers one tool per operation. The input schema is the operation's parameter table as JSON Schema, with `additionalProperties: false`.
- The result is the operation's JSON result as `structuredContent`, plus a short text rendering in `content`. An operation error is a tool result with `isError: true` and `structuredContent: {"error": <error object>}`. Surface errors (`layer_unavailable`, `unauthorized`) use the same envelope. Parameter and schema violations MUST be returned as a tool result with code `invalid_args`, never as a JSON-RPC error.
- The stdio MCP surface, started by the host, proxies every tool call to the layer endpoint and applies the environment defaults of section 5.14. It holds no sessions itself.

### 6.4 CLI

- Commands are named as in section 6.1. Parameters are long options, with underscores written as hyphens (`--session-id`, `--wait-ms`). Booleans are flags.
- Any string parameter accepts `@path`, which reads the value from the file at `path`, resolved against the CLI's working directory. `@-` reads stdin, and at most one parameter may use it. `@@` at the start writes a literal `@`.
  - Files are read as UTF-8, trailing newlines included, and expanded once. A file that cannot be read, or a second use of `@-`, fails with `invalid_args`.
  - MCP strings are always literal.
  - The reason: in run 6 a prompt built in an unquoted shell heredoc lost three phrases to command substitution.
- The CLI writes the JSON result to stdout. Its exit status:
  - 0 when the operation succeeds, including when it returns a `failed` invocation;
  - 1 for an operation error, with the bare error object on stderr: the same object as `structuredContent.error`;
  - 2 for `layer_unavailable` or `unauthorized`.
- `serve` starts a layer in the foreground. `init` installs the host-integration profile when the implementation offers it (section 7).
- With a reachable layer, `agent-info` and `agent-sessions` MUST each finish within 300 ms at the 95th percentile. This is measured from process start to exit, over 100 runs after one warm-up, on the machine running the conformance suite, with 8 parallel callers. The CLI is a client of the layer endpoint. Parallel invocations MUST NOT serialize on a lock of their own (run 6: Mix build-lock contention).

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

**7.3 Hooks.** Each hook is advisory. It reads the layer through `agent_sessions` only, using the `caller_id` filter and the invocation summaries, so checking never marks a result delivered. It makes no network calls outside the local layer. When the layer is unreachable it fails open with a short message.

| Hook | Host event | Behaviour |
| --- | --- | --- |
| Caller id | none | The host starts one stdio MCP surface per host session. Only a stdio MCP surface installed by this profile sets `caller_id`. It reads the host session id from its own environment (Claude Code sets `CLAUDE_CODE_SESSION_ID`) and passes it on `agent` calls without `session_id`. Hooks receive the same id in their input and filter `agent_sessions` by it. When the caller is itself a layer session, hooks filter by `parent_session_id` from `AGENT_SESSION_ID`. With neither identity, the caller-scoped hooks are unavailable and MUST NOT list unfiltered. |
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
| W1 | Run one turn non-interactively, fresh or resuming a provider session id, in a given working directory. Return a terminal outcome: success or failure, final message, provider session id, usage as reported, cost when reported. Success means the provider reported success and the process exited 0; otherwise the outcome order in 4.8 applies. | 4.1 |
| W2 | Report the provider session id as soon as the provider emits it, before the turn ends. | 4.7, 5.3, 5.19 |
| W3 | Apply the same model, effort and access options on fresh and resumed turns. | 5.8, 5.10 |
| W4 | Express `inherit` as in section 5.10: no permission flags, with Codex approval prompts off. Express each narrowing value. | 5.10 |
| W5 | Run each turn in its own process group, and report the group id, the leader's pid and the leader's start time. Then withhold the prompt until the layer releases it, which the layer does only after the recovery record is durable. If the layer's channel to the wrapper closes before release, terminate the group. Stop the whole group on request, and confirm when every member has exited, also after a turn that ended normally. | 5.12 |
| W6 | Set and unset child environment variables per turn, with unsets honoured on every spawn path. | 5.14, 5.17 |
| W7 | Deliver the prompt without an argv size limit (stdin or a file), and keep it out of the process table. | 4.1, 5.18 |
| W8 | Impose no turn timeout unless configured. | 5.16 |
| W9 | Report each failure distinctly with its detail (exit status, signal, stderr tail): missing binary or spawn failure, provider-reported failure, nonzero exit or exit zero without a terminal report, unparseable output. | 4.8 |
| W10 | Report usage as per-turn counters, or as running totals with that stated, so the layer can apply 5.15. | 5.15 |
| W11 | Report whether the provider reports cost. | 4.7 |
| W12 | Check whether a provider session id exists for a working directory, without running a turn. | 5.9 |

Optional:

- W13: steer or interrupt a turn without ending it. The current operations do not use it (section 11).
- W14: report provider events while a turn runs, at least their kind and tool names, so the layer can fill `progress` (section 4.7).

A wrapper gap MUST be fixed in the wrapper, not worked around in the layer. Run 6 found two such gaps, codex_wrapper #142 and claude_wrapper #338. Both were already fixed upstream. Both had been hidden by logic that the GenAgent adapters carried themselves.

## 9. Conformance

An implementation conforms when it passes C1 to C24 (C23 when it offers W14), against fake CLIs in automated tests, and C1 to C5 and C7 against the real CLIs in a live smoke run. A fake CLI is a test executable that records its argv, environment and stdin, and emits provider-shaped output on cue. A wrapper test double, which reports outcomes and cleanup evidence on cue, is allowed where a scenario says so.

| Id | Scenario | Checks |
| --- | --- | --- |
| C1 | Single-use: one `agent` call with a whole task, `agent_result` until terminal, `agent_stop`. | Terminal result. The ended record is readable. No member of any of the session's turn process groups remains. |
| C2 | Counterpart: one session, three turns, plus two follow-ups submitted while the second turn runs. | The same provider session id on every turn. The invocations run in submission order. Per-turn usage on each. |
| C3 | Recursive: a parent session, running with an access value that permits running the CLI and reaching the loopback endpoint (live: Claude with `bypass_permissions`), starts a child session of either provider through the MCP surface and through the CLI, with no configuration, using the variables in 5.14. The child runs two turns and is stopped by its parent. | The child's `parent_session_id` and depth. Both children are visible in the same layer and listed with `include_ended`. |
| C4 | Restart: during a running first turn, after its `provider_session_id` is reported, shut the layer down gracefully while a caller waits on the invocation. Start a new layer and call `agent` with `resume`. Repeat with the layer killed instead, leaving the fake CLI running; then with a recovery record whose leader pid now belongs to an unrelated process; then with a recovered group whose leader exited while a member keeps running. | The waiter receives `cancelled` with `detail.by: shutdown`. The conversation continues and the prompt is not resent. After the kill, the new layer stops the leftover process group before accepting requests, and refuses to adopt its provider session until then. The unrelated process is not signalled. For the exited leader, the layer keeps the record and the ownership, signals nothing, and still serves other sessions. |
| C5 | Cleanup: cancel a turn whose fake CLI has started a long-running descendant; end a turn normally with a descendant still running; cancel a turn through a wrapper test double that withholds cleanup confirmation. | First two: `cleanup` becomes `confirmed` within `cleanup_ms`, and an observer outside the layer finds no member of the turn's process group left. Third: the session is `cleaning`, new turns wait, and after `cleanup_ms` the session ends with `cleanup_unconfirmed` and keeps ownership, also after its record is evicted. |
| C6 | Working directory: remove the cwd between turns, then restore it. | `cwd_missing` on that invocation, the CLI not started, and the next turn runs. |
| C7 | Access: a `read_only` session's resumed turn, and an `inherit` session's turns. | The fake CLI's argv carries the narrowing on the resumed turn. `inherit` passes no permission flags. Live, a write attempt in the `read_only` session fails. |
| C8 | Usage: running totals over four turns, with one turn missing its total, then a decrease. | Per-turn values follow 5.15 exactly. |
| C9 | Environment: the layer's environment holds a runtime boot variable, a parent-session marker, an operator strip entry, a credential sharing the marker's prefix, and an unrelated variable. | The child lacks the first three, and has the credential, the unrelated variable and the variables in 5.14. |
| C10 | Surfaces: C1 to C3 and C11 through the stdio MCP surface, the CLI and the layer endpoint directly. | Results are identical apart from ids, timestamps, durations, text, usage values and `caller_id`. Error codes are identical. |
| C11 | Errors: trigger every operation error code in 4.8. | Each returns its code and creates or changes nothing. |
| C12 | Races: a cancel racing completion; submissions racing a cancel; a stop during a wait; two `agent` calls with the same `name`. | The rules in 5.2, 5.4 and 5.7. |
| C13 | Waits and disconnects: `wait_ms` expiry on queued and running invocations; a caller that disconnects mid-wait. | The pending status is returned at expiry. The turn continues and its result is held. |
| C14 | Retention: exceed `max_results`, `max_ended` and `idle_ms`. | Eviction order. Pending invocations are never evicted. `end_reason: idle`. |
| C15 | Idempotency: resend with the same `request_id`, then with the same key and different parameters. | The original invocation, then `request_conflict`. |
| C16 | Long turn: a fake turn that runs past every wrapper default idle bound, at least 10 minutes. | It completes. |
| C17 | Prompt handling: a prompt over 1 MiB containing a 64-byte sentinel, sent to a fake CLI that echoes it to stderr and exits nonzero. | The sentinel is in no process's argv, and in no log, telemetry event or error `detail`. |
| C18 | CLI arguments: `@path`, `@-` and `@@`, and timing of `agent-info` and `agent-sessions` under 8 parallel callers. | Exact values. The bound in 6.4 for both commands. |
| C19 | Endpoint and discovery: a request without a token, with a wrong token; a schema violation; two layers started at once; a stale address file; a layer with a different `spec_version` minor version; `AGENT_SESSION_LAYER` set without `AGENT_SESSION_TOKEN`. | HTTP 401 mapped to `unauthorized`; `invalid_args` as a tool result; one layer runs and the other exits; the stale file is replaced; `layer_unavailable`; `layer_unavailable` with no fallback. |
| C20 | Ownership and access: adopt a provider session owned by a live session; change the user's Claude configuration between two `inherit` turns. | `provider_session_in_use` naming the owner; the second turn sees the new configuration. |
| C21 | `agent_info` accuracy: submit every listed `provider`, `effort` and `access` value, and one unlisted value of each. | Listed values are accepted; unlisted ones fail with `invalid_option`. |
| C22 | Persistence: a session with two completed turns, an ended session, and a `queued` invocation; restart the layer gracefully, then kill it and restart. Then send a prompt to the first session, read the ended session's results, and resend an earlier `request_id`. | The first session resumes the same provider session id. The ended session's results are unchanged. The queued invocation is `cancelled` with `detail.by: shutdown` and is never resent. The `request_id` returns the original invocation. Ids are not reused. |
| C23 | Progress, with a wrapper that supports W14: a fake turn that emits messages and two tool calls, then stalls. | `progress` counts the events, names both tools, and has a `last_activity_at` that stops advancing during the stall. It contains no text. |
| C24 | Tree totals: a parent with two children and a grandchild, all reporting usage. | `tree_usage_total` of the parent equals the sum over all four. |
| H1 | Host-integration profile, when offered: `init` on both hosts; from each host, submit through the MCP tools without waiting and make no terminal read. | Tools listed under the plugin's names. Where an identity channel exists: a completion notice reaches the caller by its next turn at the latest, and the brief lists the caller's sessions. With the plugin's hooks disabled, C1 still passes. |

## 10. Evaluation of the working hypothesis (not normative)

The hypothesis in section 1 is that a provider wrapper plus a thin layer meets this spec, with no agent framework in between. An implementation supports the hypothesis when:

- **E1.** It conforms (section 9).
- **E2.** Its dependency tree contains no agent framework, meaning a library whose purpose is to model agents, their callbacks or their orchestration. For this ecosystem that means GenAgent, GenAgent Ensemble and the GenAgent backend adapters. Process, transport, serialization, telemetry and surface libraries are expected.
- **E3.** Every wrapper capability in section 8 is met by the wrapper itself. Any capability the layer had to work around counts against the hypothesis until the wrapper is fixed.
- **E4.** The three run 6 patterns, run live through it, produce results comparable to run 6.

## 11. Open questions

1. **Steering.** Should a prompt submitted during a turn be able to steer it (W13) rather than queue? Codex's app server and Claude's duplex mode can. Deferred until a live check on both providers. If adopted, it is a separate operation, `agent_steer(session_id, prompt)`, because it changes a running turn rather than creating an invocation. Decided 2026-11-01; the other questions from 0.4.1 were settled and moved into sections 2, 4.7 and 5.20.

## Appendix A. Mapping to the Elixir wrappers (non-normative)

As of claude_wrapper 0.19.0 and codex_wrapper 0.9.0. Where codex_wrapper main differs, the main state is noted.

| Id | claude_wrapper 0.19.0 | codex_wrapper 0.9.0 (main) |
| --- | --- | --- |
| W1 | Met. `Session.send/3` runs `claude -p`, with `--resume` from the second turn; `Result` has `result`, `session_id`, `cost_usd`, `usage`, `is_error`. | Met. `Session.send/3` runs `exec`, then `exec resume <thread_id>`. Main adds `CodexWrapper.Turn`, whose status treats a nonzero exit as failure even after `turn.completed`. |
| W2 | Partial. `Query.execute/3` takes a `:session_observer` that reports the id at `system/init`; `Session.send/3` does not expose it. The pending `ClaudeWrapper.Run` (#351) does. | Partial. `thread.started` carries the id; `Session.send/3` reports it only after the turn. |
| W3 | Met. Session query options apply to every turn. | Met since 0.9.0 (#142, #160). |
| W4 | Met: `permission_mode`, `tools`. | Met: `sandbox`, `approval_policy`, `ignore_user_config`. |
| W5 | Partial. The default Port runner signals the CLI when its owner dies, but not its process group. `Runner.Forcola` kills the group, selected by application configuration. `ClaudeWrapper.Run` (#351) adds cancel with recorded evidence, but cleanup is `unknown` with Forcola 0.7. Reporting the group identity before the prompt, the prompt-release handshake, and confirming group exit are the gaps. | Partial. The same Port and Forcola split, and no async handle. |
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
| 5.17 | Release variables are scrubbed by the server's child environment. Parent-session markers and `MIX_QUIET` are not: in run 6 every child received the host Claude Code session's markers, including its messaging socket and token. |
| 6.2 | Reached through release rpc with the Erlang cookie. No MCP endpoint, address file or token. |
| 6.4 | The CLI is `mix gen_agent_server.ops`, run from a server checkout, without `@path`. |

## Appendix C. Native subagent tools (non-normative)

The operations are shaped after the subagent tools that Claude Code and Codex give their own sessions; see [agent-interface.md](agent-interface.md) for the comparison. The additions over them are:

- a session that outlives the caller's conversation (5.5);
- held results readable from anywhere (4.2);
- adopting provider sessions (5.9);
- ended records (5.13).

As in both native tools, a call has no permission parameter beyond `access`, and there is no turn limit.

## Appendix D. Changes (non-normative)

### 0.4.1 to 0.5

Owner decisions on the open questions, 2026-11-01:

- **Progress without content.** `progress` on running invocations, with optional wrapper capability W14 (4.7, 8, C23).
- **Persistence.** Sessions, held results, ended records and idempotency keys persist. Live sessions return as dormant handles that resume by provider id, and interrupted turns are never resent (5.20, C22). Ids are unique across restarts (5.2).
- **Tree totals.** `tree_usage_total` and `tree_cost_usd_total` (4.7, C24).
- **Steering.** Deferred until a live check; it would be a separate `agent_steer` operation (11).
- **Out of scope:** worktree isolation, messages without a turn, budget enforcement, and native subagent routing, each with its reason (2).

### 0.4 to 0.4.1

From the fourth-round reviews:

- Discovery and the version row now match 5.14 and 6.2.
- `detail.owner` can be `recovery`.
- The provider session id is durable before it is reported.
- Per-turn counters are converted (5.15).
- C3 fixes its access, and a loopback-blocking Codex sandbox cannot nest.
- Process-group wording replaces "tree" throughout cleanup.
- W5 carries the prompt-release handshake.
- Recovery handles a group whose leader exited (5.12, 5.19, C4).
- One MCP protocol version every implementation supports (6.2).

### 0.3 to 0.4

From the third-round reviews, which found only small blocking items:

- **Ownership.** Kept independently of records. Eviction never releases it, and recovery records carry it across restarts (5.3, 5.12).
- **Cleanup.**
  - The guarantee is the turn's process group, with escaped descendants stated as outside it (5.12, W5).
  - Recovery records are durable before the prompt is delivered.
  - They identify the leader by pid, start time and boot id, so a reused id is never signalled.
  - `cleanup: none` is defined precisely (4.3).
- **Endpoint.**
  - An `fcntl` lock.
  - HTTP 401 before MCP dispatch.
  - Schema violations as `invalid_args` tool results.
  - MCP 2025-06-18 or later.
  - Minor-version checks while the spec is 0.x (6.2, 6.3).
  - The CLI's stderr carries the bare error object (6.4).
- **Usage.** Counter meanings are normalized across providers (4.7).
- **Environment.** An exact pass-through set. Overrides cannot replace the session variables. Both discovery variables or neither, with no fallback (5.14, 5.17).
- **Nesting.** Conditional on access permitting the needed tools (5.14).
- **Profile.** Only the profile's stdio surface sets `caller_id`. Caller-scoped hooks need an identity channel (7.3).
- **Conformance.** C4, C5, C10, C18, C19 and H1 updated to match.

### 0.2 to 0.3

From the second-round reviews of 0.2:

- **Interoperability boundary.**
  - The layer endpoint is an MCP server over loopback HTTP with a bearer token. The address file path and schema are fixed, there is a single-instance lock, and stale and version-mismatch rules are defined (6.2).
  - Surfaces are thin clients of that endpoint.
- **State machine.**
  - One table of states against operations (4.9).
  - Stop closes admission and is never reopened. Ownership survives eviction.
  - Descendants are stopped after every turn.
  - Process groups are recorded, so the next layer cleans up after a crash (5.12).
- **Idempotency.** Scope, ordering against the other admission checks, and which parameters are compared (5.6).
- **Delivery.** `agent_sessions` carries invocation summaries, and listing never marks a result delivered (4.5). Hooks read only through it (7.3).
- **Defaults.** Implicit `parent_session_id` and `caller_id` apply only when starting a session (5.14). The caller-id channel is defined (7.3).
- **Errors.**
  - Acceptance decides the channel.
  - One precedence order for turn outcomes.
  - Required `detail` fields per code.
  - Prompt spans redacted from provider stderr (4.8).
- **Usage.** Per-counter baselines, normative counter names, and fresh baselines at zero (4.7, 5.15).
- **Environment.** A normative list of parent-session markers, with run 6's leak of the host session's messaging token as evidence (5.17).
- **Smaller changes.**
  - `layer_instance_id` and `started_inside_agent_session` in `agent_info`.
  - `agent_info` must match what the layer accepts.
  - The Claude `read_only` tool set is defined.
  - Codex resume ignores `cwd`.
  - `queued` counts invocations queued now.
- **Conformance.**
  - Observable oracles for cleanup, restart, crash and redaction (C4, C5, C17).
  - C7 is part of the live smoke run.
  - C10 also runs the error cases.
  - New C19 to C21.
  - H1 avoids the read that would suppress the notice.
  - A defined timing method (6.4).

### 0.1 to 0.2

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

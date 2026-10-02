I’ll trace the current hook docs and call/dispatch paths, then report the remaining gap and the smallest scoped edits.

## Claims that still hold

- `pre_run/1` runs synchronously in the agent process. The server notes that messages arriving during the hook wait in its queue and are processed after it returns ([server.ex](/private/tmp/gen_agent_issue_230_hooks/lib/gen_agent/server.ex:51)). The callback docs say it delays the first turn but do not explain that synchronous calls wait too ([gen_agent.ex](/private/tmp/gen_agent_issue_230_hooks/lib/gen_agent.ex:304)).
- `pre_turn/2` runs in the agent process before the prompt task is started ([gen_agent.ex](/private/tmp/gen_agent_issue_230_hooks/lib/gen_agent.ex:327), [server.ex](/private/tmp/gen_agent_issue_230_hooks/lib/gen_agent/server.ex:1097)). Its docs recommend sleeping for rate limiting without saying that this delays processing of synchronous calls on every dispatch ([gen_agent.ex](/private/tmp/gen_agent_issue_230_hooks/lib/gen_agent.ex:335)).
- Synchronous APIs use `:gen_statem.call/3`, and their default timeout is `:infinity` ([gen_agent.ex](/private/tmp/gen_agent_issue_230_hooks/lib/gen_agent.ex:473), [gen_agent.ex](/private/tmp/gen_agent_issue_230_hooks/lib/gen_agent.ex:877), [gen_agent.ex](/private/tmp/gen_agent_issue_230_hooks/lib/gen_agent.ex:917)). This includes APIs such as `status/2`, `poll/3`, and `tell/3`.
- The docs do not provide a compact table of callback execution locations. They identify `handle_stream_event/2` as running in the prompt task, but other callbacks’ locations are not summarized ([gen_agent.ex](/private/tmp/gen_agent_issue_230_hooks/lib/gen_agent.ex:119)).

## Already resolved or qualified

- `start_agent/2` returning before `pre_run/1` completes is already documented ([gen_agent.ex](/private/tmp/gen_agent_issue_230_hooks/lib/gen_agent.ex:308)).
- `notify/2` is explicitly documented as an asynchronous cast that returns immediately ([gen_agent.ex](/private/tmp/gen_agent_issue_230_hooks/lib/gen_agent.ex:754)). The claim should therefore be limited to synchronous calls handled by the agent process. Direct registry lookup is also separate from those calls.
- Prompt execution and `handle_stream_event/2` running in the prompt task are already documented ([gen_agent.ex](/private/tmp/gen_agent_issue_230_hooks/lib/gen_agent.ex:145), [gen_agent.ex](/private/tmp/gen_agent_issue_230_hooks/lib/gen_agent.ex:284)).

## Smallest change

- **`lib/gen_agent.ex`**: Expand the `pre_run/1` and `pre_turn/2` docs to say that while each hook runs in the agent process, synchronous calls handled by that process wait. State that their default caller timeout is `:infinity`; clarify that `start_agent/2` returns before `pre_run/1`, while asynchronous casts such as `notify/2` and direct registry lookup do not wait for hook completion. Add a compact callback-location table covering callbacks in the agent process, `handle_stream_event/2` in the prompt task, and backend prompt/stream work in that task.
- **`lib/gen_agent/server.ex`**: No implementation change appears necessary. The current dispatch and callback paths already support the documented behavior. Add behavioral tests only if needed to demonstrate that a gated hook delays representative synchronous calls while `start_agent/2` returns and cast admission is asynchronous.
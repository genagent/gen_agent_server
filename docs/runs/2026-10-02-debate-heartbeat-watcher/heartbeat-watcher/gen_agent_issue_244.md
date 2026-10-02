Found by the 2026-10-01 review at `b8f8ab4` and re-verified against `main` at `1a03608` by a read-only Codex worker in a `gen_agent_server` verification pool (genagent/gen_agent_server#25). One verifier per finding: treat file and line references as the starting point for the fix, and re-check them.

## Problem

### Heartbeat and Watcher guide agents drop work when a turn fails

Heartbeat.Agent clears state.observations when it returns the summary prompt and has no handle_error/3, so a failed summary turn discards the whole batch. Watcher.Agent likewise has no handle_error/3, so a failed diagnosis or welcome turn leaves no record in state.

**Verification on current main.** `Heartbeat.Agent` clears `observations` when it dispatches the summary prompt, before the turn succeeds (guides/patterns/heartbeat.md:98-107). Neither guide agent defines `handle_error/3`; the default preserves the current state and does not retry (lib/gen_agent.ex:415-416). Thus a failed heartbeat turn leaves that batch absent from agent state. `Watcher.Agent` dispatches diagnosis and welcome prompts without recording their events, and adds an action only on success (guides/patterns/watcher.md:90-116). A failed turn leaves no record of that event in Watcher’s agent state.

### Heartbeat guide statement that ticking a halted agent is harmless is not accurate

The 'Self-halting heartbeat' variation says notifying a halted agent is 'harmless, but noisy'. handle_event/2 still runs on a halted agent, and any clause that returns {:prompt, ...} has its prompt queued in the mailbox and its state change applied. With the guide's own tick clause, observations are cleared and one prompt is queued per tick, all of which dispatch on resume/1.

**Verification on current main.** The guide calls ticks sent to a halted agent “harmless” (`guides/patterns/heartbeat.md:198`). But notifications still reach `handle_event/2` while idle and halted; a `{:prompt, ...}` return applies the new state and queues the prompt (`lib/gen_agent/server.ex:773`, `lib/gen_agent/server.ex:793`). Resume starts draining that queue (`lib/gen_agent/server.ex:486`). The detail overstates the effect: the guide’s tick clause clears observations, so later ticks without enough new observations do **not** queue another prompt (`guides/patterns/heartbeat.md:92`).

### Heartbeat.Ticker in the guide is not tied to the agent's lifetime and cannot be supervised as written

The ticker is a Task linked to the caller that loops forever on GenAgent.notify/2. The 'Using it' snippet stops the agent and leaves the ticker running. notify/2 to an unregistered name returns :ok, so the ticker never fails; if an agent is started again under the same name it receives ticks from the old ticker as well as the new one. The module has start_link/2 and no child_spec/1, so it cannot be listed in a supervision tree directly.

**Verification on current main.** I’ll read the cited guide and the relevant GenAgent code.

VERDICT: CONFIRMED

`Heartbeat.Ticker.start_link/2` links a looping Task to its caller, not to the agent (`guides/patterns/heartbeat.md:129–137`). The example stops only the agent (`guides/patterns/heartbeat.md:171`); `GenAgent.stop/2` terminates that agent process (`lib/gen_agent.ex:861–865`). `notify/2` is an asynchronous cast that returns `:ok` (`lib/gen_agent.ex:690–693, 705–707`), so the ticker can continue while the name is unregistered and send ticks to a later agent registered under it. The Ticker module defines no `child_spec/1`, so it cannot be used directly as a supervisor child.

### Watcher and Heartbeat guides describe pre-0.3 notification semantics

The guides were last changed before 0.2.1 and do not reflect bounded pending inputs. They state that the mailbox 'can fill up' and that deferred ticks are never dropped. In 0.3 deferred notifications and queued prompts are bounded, notify/2 drops silently on overflow with only telemetry, event-generated prompts that cannot be queued are reported to handle_error/3 as {:overloaded, info}, and notify_ack/3 exists for admission results. None of the five guides mention notify_ack/3, tell_with_completion/4, interrupt_request/3 or runtime_snapshot/2.

**Verification on current main.** Heartbeat says deferred ticks do not drop, and Watcher warns that the mailbox can fill up without describing admission limits (guides/patterns/heartbeat.md:43–46; guides/patterns/watcher.md:159–162). Current code bounds queued prompts and notifications (lib/gen_agent/server.ex:652–705). `notify/2` always returns `:ok` even when a later rejection emits telemetry; `notify_ack/3` reports admission (lib/gen_agent.ex:678–711). A deferred event’s generated prompt can be rejected with an overload reason passed to `handle_error/3` (lib/gen_agent/server.ex:1208–1230). The pattern guides contain no mention of `notify_ack`, `tell_with_completion`, `interrupt_request`, or `runtime_snapshot`.

### Supervisor, Watcher and Heartbeat scenario tests have drifted from their guides; Supervisor test leaves workers running

The Supervisor scenario uses a different protocol from supervisor.md and covers none of the guide's failure handling; it stops only the coordinator, leaving three halted worker agents under GenAgent.AgentSupervisor for the rest of the test run. The Watcher and Heartbeat scenarios keep the same topology as their guides but use different state shapes and do not exercise Heartbeat.Ticker.

**Verification on current main.** The Supervisor scenario uses `:go` and results keyed by subtask; the guide uses `{:sub_task, task}` and results keyed by worker name (test/scenarios/supervisor_scenario_test.exs:47,121; guides/patterns/supervisor.md:155,252). Its sole test covers success, while the guide handles empty plans and worker failures (test/scenarios/supervisor_scenario_test.exs:139; guides/patterns/supervisor.md:141,159). Workers halt but remain alive; the test stops only the coordinator (test/scenarios/supervisor_scenario_test.exs:55,180; lib/gen_agent/server.ex:1177). Watcher and Heartbeat retain their guides’ event topology but use different state fields (test/scenarios/watcher_scenario_test.exs:26; test/scenarios/heartbeat_scenario_test.exs:34). Heartbeat’s timer test creates its own task instead of `Heartbeat.Ticker` (test/scenarios/heartbeat_scenario_test.exs:200; guides/patterns/heartbeat.md:121).

## Acceptance

- Tests cover each case above.

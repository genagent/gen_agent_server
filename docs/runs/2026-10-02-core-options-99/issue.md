# fix(api): validate :watchdog_ms and :max_tell_results and use one channel for invalid options
https://github.com/genagent/gen_agent/issues/99

Found in a read-only review of `main` at `b8f8ab4`. Code links point at that commit; `main` has moved since (core 0.4.0).

## Problem

`start_agent/2` documents the capture and pending limits but mentions `:watchdog_ms` only as an example of a stripped key and never mentions `:max_tell_results` (default 100, the poll result cache bound). Neither is validated. An invalid `:watchdog_ms` is accepted at start and crashes the agent on its first prompt. Missing `:name` or `:backend` raises KeyError in the caller, an invalid capture limit returns `{:error, %ArgumentError{}}` with a crash report, and `:task_supervisor` passed to `start_agent/2` is silently forwarded to `init_agent/1`.

**Evidence.** [`lib/gen_agent/server.ex:121-122`](https://github.com/genagent/gen_agent/blob/b8f8ab4/lib/gen_agent/server.ex#L121-L122) read both options with defaults (`@default_watchdog_ms :timer.minutes(10)` at line 20, `@default_max_tell_results 100` at line 21); lines 139-144 validate only the six capture and pending limits. [`lib/gen_agent/server.ex:202`](https://github.com/genagent/gen_agent/blob/b8f8ab4/lib/gen_agent/server.ex#L202) passes `data.watchdog_ms` to `{:state_timeout, ...}`. [`lib/gen_agent.ex:485-487`](https://github.com/genagent/gen_agent/blob/b8f8ab4/lib/gen_agent.ex#L485-L487) says only "GenAgent-level knobs (like `:watchdog_ms`) are recognized and stripped"; [`README.md:176`](https://github.com/genagent/gen_agent/blob/b8f8ab4/README.md#L176) says "Configurable per agent" without naming the option; grep finds no mention of `max_tell_results` in any .md file. Reproduced: `start_agent(..., watchdog_ms: -5)` returned `{:ok, pid}`; the first `ask` exited with `{:bad_action_from_state_function, {:state_timeout, -5, :watchdog}}` and the agent died. `start_agent(..., max_events_per_turn: 0)` returned `{:error, %ArgumentError{}}`. `start_agent(EchoOpts, name: "p", backend: Mock, task_supervisor: X, watchdog_ms: 1, foo: :bar)` delivered `[task_supervisor: X, foo: :bar]` to init_agent (the Keyword.split list at [`lib/gen_agent.ex:529-540`](https://github.com/genagent/gen_agent/blob/b8f8ab4/lib/gen_agent.ex#L529-L540) omits `:task_supervisor`).

**Scenario.** An application reads the watchdog from config and passes `watchdog_ms: "600000"` or a negative value. Observed: start succeeds, the first prompt kills the agent and its caller exits. Expected: start fails with a clear error. Separately, a user who needs more than 100 retained tell results has no documented option.

Reproduction from the review (private checkout, stub backend or fake CLI, no provider called):

```text
In a private copy of origin/main, test file using GenAgent.Backends.Mock and a minimal `use GenAgent` module (EchoOpts) whose init_agent/1 echoes opts to the test pid:

{:ok, pid} = GenAgent.start_agent(EchoOpts, name: "wd", backend: Mock, watchdog_ms: -5, scripts: [[GenAgent.Event.new(:result, %{text: "ok"})]])
GenAgent.ask("wd", "hi", 2_000)
# exits: {{:bad_action_from_state_function, {:state_timeout, -5, :watchdog}}, _}; agent DOWN with same reason. Same for "600000" and :never.

{:ok, _} = GenAgent.start_agent(EchoOpts, name: "m", backend: Mock, max_tell_results: 0, scripts: [...])
{:ok, ref} = GenAgent.tell("m", "x"); Process.sleep(200); GenAgent.poll("m", ref)
# => {:error, :not_found}

GenAgent.start_agent(EchoOpts, backend: Mock)            # raises KeyError (key :name)
GenAgent.start_agent(EchoOpts, name: "c", backend: Mock, max_events_per_turn: 0)  # {:error, %ArgumentError{}}
GenAgent.start_agent(EchoOpts, name: "p", backend: Mock, task_supervisor: X, watchdog_ms: 1, foo: :bar)
# init_agent/1 receives [task_supervisor: X, foo: :bar]; server uses GenAgent.TaskSupervisor
```

## Proposed fix

- Validate `:watchdog_ms` (positive integer or `:infinity`) and `:max_tell_results` (non-negative integer) in init alongside the other limits, document both with defaults and units in `start_agent/2`, list every reserved key, and reject or document `:task_supervisor` in `start_agent/2`.

## Acceptance

- A regression test reproduces each scenario above and passes after the change.

## Verification

- Confirmed by an independent code trace and reproduced by running code.
- Reported independently by 3 other review passes.


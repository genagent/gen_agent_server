Found in a read-only review of `main` at `b8f8ab4`. Code links point at that commit; `main` has moved since (core 0.4.0).

## Problem

start_session/1 ([`integrations/claude/lib/gen_agent/backends/claude.ex:58-67`](https://github.com/genagent/gen_agent/blob/b8f8ab4/integrations/claude/lib/gen_agent/backends/claude.ex#L58-L67)) stores options unchecked and always returns {:ok, session}. ClaudeWrapper.stream/2 builds CLI args lazily inside Stream.resource, so an invalid :permission_mode or :effort raises ArgumentError inside the prompt task and each ask returns {:error, {:task_crashed, _}} (every turn, not only the first); the rescue in prompt/2 (claude.ex:78-79) does not see it. A non-binary :json_schema raises FunctionClauseError in ClaudeWrapper.Command.shell_escape/1 at spawn time with the same result. Unknown keys and list options given as a non-list (:allowed_tools, :disallowed_tools, :tools) are dropped by ClaudeWrapper.Query.apply_opts/2 (query.ex:554, 525-532) with no signal, so an intended tool or permission restriction can be absent from the CLI invocation. The gen_agent_claude docs do not mention this; the Codex backend validates at start. A fix needs explicit key and shape checks in start_session/1; calling Query.build_args/1 at start only catches the enum cases.

**Evidence.** claude.ex:58-67 start_session/1; claude.ex:78-79 rescue only covers eager code. claude_wrapper 0.14.4 telemetry.ex:117-124 wraps the stream start in Stream.resource, so query.ex:694-701 build_args runs at enumeration time; query.ex:553-554 `defp apply_opt(_other, q), do: q`; query.ex:525-526 allowed_tools requires a list. Probes: permission_mode: :acceptEdits returned {:error, {:task_crashed, {%ArgumentError{message: "invalid permission_mode :acceptEdits; ..."}, ...}}} from the first ask; json_schema given as a map returned {:error, {:task_crashed, {:function_clause, ...}}}; Query.apply_opts(allowed_tools: "Read", permision_mode: :plan) built args with neither flag.

**Scenario.** Developer writes allowed_tools: "Read" (string instead of list) intending a read-only agent. Observed: the option is dropped and the agent runs with the default tool set. Expected: start_agent/2 returns an error naming the invalid option.

Reproduction from the review (private checkout, stub backend or fake CLI, no provider called):

```text
- opts = [permission_mode: :acceptEdits]: start_agent -> {:ok, _}; GenAgent.ask(n, "hello") -> {:error, {:task_crashed, {%ArgumentError{message: "invalid permission_mode :acceptEdits; expected one of [...]"}, _}}}; second ask also :error.
- opts = [effort: :extreme]: same shape.
- opts = [json_schema: %{"type" => "object"}]: ask -> {:error, {:task_crashed, {:function_clause, [{Regex, ...}]}}}.
- opts = [allowed_tools: "Read", permision_mode: :plan, sandbox: :read_only]: ask -> {:ok, _}; argv log: `--verbose --print --output-format stream-json --include-partial-messages -- hello`.
- control opts = [allowed_tools: ["Read"], permission_mode: :plan]: argv log: `--verbose --print --output-format stream-json --permission-mode plan --allowed-tools Read --include-partial-messages -- hello`.
- Direct: {:ok, s} = Claude.start_session(binary: fake, permission_mode: :acceptEdits); Claude.prompt(s, "hello") -> {:ok, stream, _}; Enum.to_list(stream) raises ArgumentError.
```

## Proposed fix

- Validate in start_session/1: check enum values for :permission_mode and :effort, list shape for :allowed_tools, :disallowed_tools, :tools, :add_dir, :mcp_config, binary shape for :json_schema, and warn or error on keys that neither ClaudeWrapper.Config nor Query.apply_opts/2 recognises. A cheap way to catch value errors is to build the Query and call Query.build_args/1 once at start.

## Acceptance

- A regression test reproduces each scenario above and passes after the change.

## Verification

- Confirmed by an independent code trace and reproduced by running code.
- Reported independently by 1 other review pass.


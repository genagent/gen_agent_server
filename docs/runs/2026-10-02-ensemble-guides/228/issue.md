# docs(ensemble): fix the workflow guide examples

Found by the 2026-10-01 review at `b8f8ab4` and re-verified against `main` at `1a03608` by a read-only Codex worker in a `gen_agent_server` verification pool (genagent/gen_agent_server#25). One verifier per finding: treat file and line references as the starting point for the fix, and re-check them.

## Problem

### debate.md config example references GenAgentEnsemble.Agents.Anthropic, which does not exist

The only config example in the Debate guide uses a callback module that is not in the package, so the ensemble fails to start when the block is pasted. The same guide still calls Consensus "planned" although it ships.

**Verification on current main.** The Debate guide’s config uses `GenAgentEnsemble.Agents.Anthropic` for its second agent (`extensions/ensemble/guides/workflows/debate.md:45-65`). The package defines `GenAgentEnsemble.Agents.Simple` (`extensions/ensemble/lib/gen_agent_ensemble/agents/simple.ex:1`), but no `Agents.Anthropic` module. Startup attempts to start every configured agent (`extensions/ensemble/lib/gen_agent_ensemble/server.ex:97-105,412-420`), and core initialization calls the callback module’s `init_agent/1` (`lib/gen_agent/server.ex:147`), so that entry fails. The guide also labels Consensus “planned” (`debate.md:40-41`), although its strategy module exists (`extensions/ensemble/lib/gen_agent_ensemble/strategies/consensus.ex:1`).

### supervisor.md drifts from the strategy in four places

The status examples show phase shapes the strategy never returns, the empty-decomposition statement contradicts the code and its test, the guide says Supervisor cannot be config-driven while config.exs ships a config template for it, and a raising user function is described as a halt.

**Verification on current main.** I’ll compare the guide’s four statements with the strategy, tests, and config.

VERDICT: CONFIRMED

The guide shows token-bearing `:decomposing` and `:fanout` phases (supervisor.md:121–124); `handle_status/1` returns `:decomposing` or `{:fanning_out, done, total}` (supervisor.ex:240–255). For an empty decomposition, the strategy returns the coordinator’s response without calling the synthesizer (supervisor.ex:118–123), contrary to supervisor.md:141–143. The “not config-driveable” claim (supervisor.md:62–66) conflicts with the Supervisor template using function references in config.exs:120–135. User functions are called directly (supervisor.ex:104,146); `call_strategy/3` has no exception handling (server.ex:671–674), so a raise crashes the Server callback rather than issuing a `:halt` op as supervisor.md:162–164 suggests.

### consensus.md: config example is not runnable as written and the parse-rate advice points at signals that do not exist

The Config block defines a module and calls an undefined `system_prompt()` inside what is presented as a config file. The Gotchas section tells readers to watch abstain rates via status or logs, but the strategy neither logs parse failures nor reports abstains in status. The decision-extraction example binds `summary` to the start_link result.

**Verification on current main.** The Config block defines `DecisionParser` but calls `system_prompt()` three times without defining it, so it cannot run as pasted (`extensions/ensemble/guides/workflows/consensus.md:57-98`). Defining a module in a config file is valid; the undefined function is the blocker. Parse failures become `nil` verdicts (`extensions/ensemble/lib/gen_agent_ensemble/strategies/consensus.ex:166-173`), while status reports only round and response counts, with no abstain count (`consensus.ex:374-395`). The strategy has no parse-failure logging. The guide nevertheless recommends watching parse rates via status or logs (`consensus.md:212-216`). Its extraction example first binds `summary` to `E.start_link/1`, then rebinds it to the response text (`consensus.md:155-166`).

### Pipeline guide points to a telemetry event that does not carry stage output

pipeline.md says intermediate stage outputs can be read from [:gen_agent, :prompt, :stop] telemetry. That event carries duration, agent name, ref and agent_state only. With Agents.Simple the agent_state is an empty map, so the intermediate text is not observable that way.

**Verification on current main.** The event payload determines whether that guide instruction works.

VERDICT: CONFIRMED

The guide directs readers to `[:gen_agent, :prompt, :stop]` for intermediate outputs (pipeline.md:119–122). That event emits only duration plus `agent`, `ref`, and `agent_state`; it has no response text (lib/gen_agent/server.ex:1449–1454). `Agents.Simple` initializes its agent state as `%{}` and leaves it unchanged on responses (extensions/ensemble/lib/gen_agent_ensemble/agents/simple.ex:33–37). Pipeline forwards intermediate `response.text` as the next stage’s prompt but returns only the last stage’s response (extensions/ensemble/lib/gen_agent_ensemble/strategies/pipeline.ex:78–89).

## Acceptance

- Tests cover each case above.


https://github.com/genagent/gen_agent/issues/228

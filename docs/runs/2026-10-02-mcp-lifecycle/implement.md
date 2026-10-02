I've implemented the MCP lifecycle surface, but none of it has been compiled or run. The sandbox required approval for every `mix` command. Please run `mix format`, `mix compile --warnings-as-errors`, `mix test` and the release smoke script. My hand-wrapped lines may not match the formatter.

**Effort:** I included it. Claude takes it as its adapter `:effort` option, with the adapter's own enum. Codex gets a server-generated `model_reasoning_effort="…"` override, limited to `low`, `medium`, `high`. The new Codex test runs the real adapter against a fake `codex` binary and checks both fresh and resumed commands. That test is unrun, so the claim isn't proven until it passes.

**Files changed**
- `lib/gen_agent_server/instance_spec.ex` (new): strict parser for the creation config. It validates names, duplicates, provider, model shape, absolute existing cwd, limits, route count, and provider-specific modes and effort. It rejects unknown keys, so modules, backend options and pattern specs can't get in. It uses fixed atom lists, so nothing creates atoms from client strings.
- `lib/gen_agent_server/providers.ex`: adds `:effort` and `efforts/1`. It also adds a trusted `:provider_overrides` app-env hook, which no client operation can set, used only for test backends.
- `lib/gen_agent_server/instance.ex`, `invocations.ex`: carry the sanitized creation description. A new `describe` call reports routes, strategy and limits. Instances not made by `create_instance` report `configured: false` with route names only.
- `lib/gen_agent_server.ex`: new `create_instance/2` and `describe_instance/1`. Creation validates first, rejects a duplicate before starting, and maps a duplicate-start race to `:instance_exists`. A start failure returns `:instance_start_failed`, with no pids.
- `lib/gen_agent_server/ops.ex`: new `create_instance` (mutating) and `describe_instance` (read-only) operations. `create_instance` carries a documented config schema, and the `invalid_config` error code is new.
- `lib/gen_agent_server/ops.ex`: `stop_instance` is unchanged apart from a new summary: "Its routes and stored results are discarded."
- `lib/gen_agent_server/mcp.ex`, `mcp/tools.ex`, `mcp/server.ex`: the three new MCP tools. Their schemas come from `Ops.json_schema`, so they can't drift. The original six tools are untouched, and the moduledoc documents the workflow.
- `test/gen_agent_server_lifecycle_test.exs` (new):
  - The Ops and MCP tests cover create, describe, invoke, repeatable result and stop, and instance isolation.
  - They also cover about 30 invalid configs that must start no backend, 8-way concurrent creation, and a protected default.
  - A recording backend stands in for Claude, to show model, effort and mode reach the backend.
  - The fake-`codex` test covers fresh and resumed turns.
- `test/gen_agent_server_mcp_test.exs`: the catalogue now expects nine tools, `stop_instance` is removed from the "not callable" lists, and a test checks the original six tools' schemas.
- `examples/mcp_release_smoke.exs`: extended for the nine tools. It creates an echo-only instance, describes it, rejects a duplicate and a bad claude model, asks, checks the default is protected, then stops and confirms it is gone. Provider routes need a CLI and credentials, so model selection is covered only in the test suite.
- `README.md`: the client workflow, config keys and limits, edit opt-ins, the tool approval guidance, and the limitations (immutable at creation, one VM and result store per stdio client, volatile, no reconnect across processes).

**Decisions you may want to override**
- `stop_instance` is now reachable from MCP, so the old "unreachable" wording is gone from the docs.
- `cwd` must be absolute.
- Models are checked for shape only (no leading `-`, up to 128 characters), not against a provider list.
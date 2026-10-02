I’ll keep this read-only and report the code evidence and smallest remaining change.


The lifecycle gap still holds. Instance isolation, provider defaults, model forwarding, and default-instance protection already exist underneath MCP. The locked Codex adapter also forwards config overrides on both fresh and resumed turns, so effort support has a viable path without exposing arbitrary options.


Checked `ef0c3ba0b8617caea0db364b4fc20df5e33b6ac1`; the working tree is clean. The issue remains valid, but most runtime infrastructure already exists. No files changed, tests run, or network commands used.

**Claims that still hold**

- **MCP exposes exactly six tools, with no creation, configuration inspection, or stopping.** The allowlist is in [mcp.ex:21](/private/tmp/gen_agent_server_claude_023/lib/gen_agent_server/mcp.ex:21), and registration matches it in [server.ex:16](/private/tmp/gen_agent_server_claude_023/lib/gen_agent_server/mcp/server.ex:16). Ops has `stop_instance`, but no creation or description operation.
- **Configuration discovery is missing.** Invocation state retains route names and limits, but discards provider/model configuration: [invocations.ex:53](/private/tmp/gen_agent_server_claude_023/lib/gen_agent_server/invocations.ex:53). `status` adds routes to Ensemble status; it does not return the requested configuration: [gen_agent_server.ex:54](/private/tmp/gen_agent_server_claude_023/lib/gen_agent_server.ex:54).
- **Validation is insufficient for exposing creation directly.** `start_instance` only guards argument types: [gen_agent_server.ex:20](/private/tmp/gen_agent_server_claude_023/lib/gen_agent_server.ex:20). Limits and duplicate routes are checked in `Invocations.init`, after the Ensemble child starts: [instance.ex:24](/private/tmp/gen_agent_server_claude_023/lib/gen_agent_server/instance.ex:24), [invocations.ex:60](/private/tmp/gen_agent_server_claude_023/lib/gen_agent_server/invocations.ex:60). Invalid model values are silently omitted by [providers.ex:72](/private/tmp/gen_agent_server_claude_023/lib/gen_agent_server/providers.ex:72).
- **PatternSpec should remain outside this surface.** It supports seven strategies and converts consensus verdict words into atoms: [pattern_spec.ex:37](/private/tmp/gen_agent_server_claude_023/lib/gen_agent_server/pattern_spec.ex:37), [pattern_spec.ex:300](/private/tmp/gen_agent_server_claude_023/lib/gen_agent_server/pattern_spec.ex:300).
- **Existing tests do not cover MCP lifecycle or provider selection.** MCP isolation tests create instances through the Elixir API: [gen_agent_server_mcp_test.exs:84](/private/tmp/gen_agent_server_claude_023/test/gen_agent_server_mcp_test.exs:84). The packaged smoke checks six tools and default Echo invocation/results: [mcp_release_smoke.exs:8](/private/tmp/gen_agent_server_claude_023/examples/mcp_release_smoke.exs:8).

**Already implemented and reusable**

- **Named switchboards and isolated results:** [instance.ex:20](/private/tmp/gen_agent_server_claude_023/lib/gen_agent_server/instance.ex:20), [invocations.ex:33](/private/tmp/gen_agent_server_claude_023/lib/gen_agent_server/invocations.ex:33).
- **Provider allowlist, read-only defaults, explicit edit modes, cwd checking, and model forwarding:** [providers.ex:11](/private/tmp/gen_agent_server_claude_023/lib/gen_agent_server/providers.ex:11), [providers.ex:38](/private/tmp/gen_agent_server_claude_023/lib/gen_agent_server/providers.ex:38). These need a strict data validator ahead of them, not replacement.
- **Default-instance stop protection:** [gen_agent_server.ex:39](/private/tmp/gen_agent_server_claude_023/lib/gen_agent_server.ex:39). Ops already exposes the protected operation at [ops.ex:140](/private/tmp/gen_agent_server_claude_023/lib/gen_agent_server/ops.ex:140).
- **Shared JSON operation path and error envelope:** [ops.ex:184](/private/tmp/gen_agent_server_claude_023/lib/gen_agent_server/ops.ex:184), [ops/remote.ex:23](/private/tmp/gen_agent_server_claude_023/lib/gen_agent_server/ops/remote.ex:23).
- **Per-stdio-process isolation is already documented:** [README.md:254](/private/tmp/gen_agent_server_claude_023/README.md:254). Creation volatility and the new workflow still need documenting.

**Effort finding**

The lock pins `gen_agent_codex` 0.4.5 and `codex_wrapper` 0.5.5: [mix.lock:7](/private/tmp/gen_agent_server_claude_023/mix.lock:7).

The adapter preserves `model` and `config_overrides` through both fresh and resumed calls: [codex.ex:234](/private/tmp/gen_agent_server_claude_023/deps/gen_agent_codex/lib/gen_agent/backends/codex.ex:234), [codex.ex:258](/private/tmp/gen_agent_server_claude_023/deps/gen_agent_codex/lib/gen_agent/backends/codex.ex:258), [codex.ex:286](/private/tmp/gen_agent_server_claude_023/deps/gen_agent_codex/lib/gen_agent/backends/codex.ex:286), [codex.ex:304](/private/tmp/gen_agent_server_claude_023/deps/gen_agent_codex/lib/gen_agent/backends/codex.ex:304). Both wrappers serialize overrides as `-c` arguments.

Thus a server-generated `model_reasoning_effort="…"` override has a supported transport path. The adapter does **not** validate that key’s values or model compatibility. Claude already validates an effort enum and preserves options when resuming: [claude.ex:141](/private/tmp/gen_agent_server_claude_023/deps/gen_agent_claude/lib/gen_agent/backends/claude.ex:141), [claude.ex:291](/private/tmp/gen_agent_server_claude_023/deps/gen_agent_claude/lib/gen_agent/backends/claude.ex:291). This is source evidence, not an executed provider probe.

**Smallest concrete change**

1. **Add `lib/gen_agent_server/instance_spec.ex`.** A narrow parser for a switchboard configuration containing one or more named routes. Validate every field before startup: names, duplicates, provider, bounded nonblank model strings, existing cwd, positive bounded limits, and provider-specific mode/effort enums. Reject unknown nested keys, modules, backend options, and pattern specs. Build only fixed agent modules through `Providers.backend_opts/2`.

2. **Edit `providers.ex`.** Add validated effort translation: Claude’s fixed enum; Codex’s fixed, server-generated config override. Reject unsupported Echo model/effort options. Include effort only when fresh/resumed tests establish preservation.

3. **Edit `ops.ex`.** Add `create_instance(name, config)` and `describe_instance(instance)`; reuse existing `stop_instance`. An object-valued `config` fits the existing CLI JSON parser. Return deterministic validation, duplicate-instance, missing-instance, and startup errors without PIDs. Handle duplicate-start races. Keep existing six operations unchanged.

4. **Edit `instance.ex`, `invocations.ex`, and `gen_agent_server.ex`.** Store sanitized creation metadata inside the instance and expose description through the existing instance lookup. Return routes, selected provider/model/effort, cwd/modes, and effective limits. For legacy/custom instances, report unavailable metadata explicitly rather than guessing or dumping backend options.

5. **Edit `mcp.ex`, `mcp/tools.ex`, and `mcp/server.ex`.** Register exactly three additional tools. Creation’s description must say it configures future provider work; stopping’s description must say it discards volatile results. Preserve existing tool schemas and behavior.

6. **Extend Ops/MCP tests and `examples/mcp_release_smoke.exs`.** Cover create → describe → invoke → repeatable result → stop, instance isolation, duplicate races, invalid configuration causing zero backend starts, protected default, and schema parity. Use trusted test-only backend/runner injection to prove selected models reach provider execution; test effort on fresh and resumed turns. Keep injection inaccessible to JSON clients.

7. **Edit `README.md` and MCP module documentation.** Document that workflow, immutable creation configuration, edit opt-ins, limits, and volatility. Clarify that discovery works only while the owning VM survives; starting a new stdio process does not reconnect to the previous store.
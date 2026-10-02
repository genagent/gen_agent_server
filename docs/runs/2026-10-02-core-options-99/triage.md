I’ll keep this review read-only and report the current behavior with file and line references.


At `3cd79d7`, the main validation bugs remain. No files were edited. Findings below are from code inspection; tests were not run because this read-only checkout has no dependencies or build artifacts.

**Claims that still hold**

- **Invalid watchdog values reach the first prompt unchecked.** Defaults remain 600,000 milliseconds and 100 cached results. Neither option is validated in [server.ex:137](/private/tmp/gen_agent_fix_99_20261002/lib/gen_agent/server.ex:137). The watchdog is passed directly to `:state_timeout` at [server.ex:310](/private/tmp/gen_agent_fix_99_20261002/lib/gen_agent/server.ex:310), preserving the reported failure path for negative integers, strings, and `:never`.
- **Invalid cache bounds are accepted.** At [server.ex:1950](/private/tmp/gen_agent_fix_99_20261002/lib/gen_agent/server.ex:1950), eviction depends on `map_size(...) > max_tell_results`. Atom or string values defeat eviction through Erlang term ordering, allowing unbounded growth. Negative integers immediately evict each result. Zero also immediately evicts results, but is valid under the proposed non-negative contract.
- **Startup error channels differ.** Missing required keys raise `KeyError` in the caller at [gen_agent.ex:586](/private/tmp/gen_agent_fix_99_20261002/lib/gen_agent.ex:586); existing tests explicitly require that behavior at [integration_test.exs:125](/private/tmp/gen_agent_fix_99_20261002/test/gen_agent/integration_test.exs:125). Invalid capture limits raise inside server initialization at [server.ex:1471](/private/tmp/gen_agent_fix_99_20261002/lib/gen_agent/server.ex:1471), retaining the startup-error/crash-report path.
- **`start_agent/2` still forwards `:task_supervisor` to `init_agent/1`.** It selects `GenAgent.TaskSupervisor` explicitly, and its option split omits the supplied key: [gen_agent.ex:554](/private/tmp/gen_agent_fix_99_20261002/lib/gen_agent.ex:554), [gen_agent.ex:590](/private/tmp/gen_agent_fix_99_20261002/lib/gen_agent.ex:590).
- **Startup documentation remains incomplete.** [gen_agent.ex:546](/private/tmp/gen_agent_fix_99_20261002/lib/gen_agent.ex:546) only mentions watchdog stripping; it does not document either option’s contract or enumerate reserved keys. [README.md:187](/private/tmp/gen_agent_fix_99_20261002/README.md:187) still says “Configurable per agent.” No Markdown file mentions `max_tell_results`.

**Already covered or qualified**

- `child_spec/2` correctly requires, consumes, and uses `:task_supervisor`; missing it raises `KeyError`. Its contract is documented at [gen_agent.ex:564](/private/tmp/gen_agent_fix_99_20261002/lib/gen_agent.ex:564), with implementation at line 580.
- The watchdog option and default are documented elsewhere, including [guides/backends.md:212](/private/tmp/gen_agent_fix_99_20261002/guides/backends.md:212). Cache retention now gets a passing mention in [gen_agent.ex:871](/private/tmp/gen_agent_fix_99_20261002/lib/gen_agent.ex:871), but still lacks configuration documentation.
- Valid cache eviction already has coverage at [request_completion_test.exs:94](/private/tmp/gen_agent_fix_99_20261002/test/gen_agent/request_completion_test.exs:94). The requested invalid-value and boundary coverage remains absent.

**Smallest concrete change**

1. **`lib/gen_agent/server.ex`:** Validate watchdog as a positive integer or `:infinity`, and cache size as a non-negative integer, before callbacks/backend initialization. Follow the existing initialization `ArgumentError` pattern so invalid limits share the established startup error channel.
2. **`lib/gen_agent.ex`:** Document both defaults, milliseconds versus result count, `:infinity`, and zero-cache behavior. Enumerate every key in `Keyword.split/2`. Explicitly document that `start_agent/2` uses the global task supervisor and forwards a supplied `:task_supervisor`; direct callers needing supervisor selection to `child_spec/2`. Preserve existing required-key exceptions and forwarding behavior. Also document that explicit `nil` currently falls back to defaults through [gen_agent.ex:1000](/private/tmp/gen_agent_fix_99_20261002/lib/gen_agent.ex:1000).
3. **`test/gen_agent/integration_test.exs`:** Add invalid watchdog cases `-5`, `"600000"`, `:never`, and `0`; invalid cache cases `-1`, `"100"`, and `:infinity`; acceptance cases watchdog `1`/`:infinity` and cache `0`/`1`. Verify zero disables retention and one evicts the oldest result after completion. Cover both startup paths, required-key exceptions, and option forwarding with an echoing callback.
4. **`README.md`:** Name `watchdog_ms`, give its units/default, and document `max_tell_results`, its default, and zero retention.

Unifying *all* errors would change explicitly tested public behavior. The scoped fix should preserve `KeyError` for missing required keys and use the existing startup error channel for invalid limits.
The issue is **still present** in this checkout. The README now documents the silent-dropping behavior, but `start_session/1` does not validate it.

### Claims that still hold

- **Options are stored without validation.** [claude.ex:63-75](integrations/claude/lib/gen_agent/backends/claude.ex:63) only rejects `no_session_persistence`, removes `stream_fn`, normalizes options, and returns a session. `resume_session/2` calls `start_session/1`, so it inherits the same gap at [claude.ex:117-120](integrations/claude/lib/gen_agent/backends/claude.ex:117).

- **Prompt rescue does not catch failures during stream enumeration.** [claude.ex:94-101](integrations/claude/lib/gen_agent/backends/claude.ex:94) calls the stream function and builds the enumerable inside a rescue, but enumeration happens later. The current code does not eagerly build or validate Claude CLI arguments at session start, so the reported lazy-error path remains possible.

- **Invalid intended restrictions can be silently dropped.** The current README explicitly says the wrapper ignores unknown keys and ignores `:allowed_tools`, `:disallowed_tools`, and `:tools` when they are not lists at [README.md:162-167](integrations/claude/README.md:162). Thus the string-valued `allowed_tools` scenario remains a security-relevant risk.

- **Malformed values documented as valid option shapes are unchecked.** For example, `:json_schema` is documented as a string at [README.md:184-188](integrations/claude/README.md:184), and the tool options as lists at [README.md:192-204](integrations/claude/README.md:192). No corresponding checks appear in `start_session/1`.

- **Tests do not cover start-time validation.** Existing `start_session/1` tests cover session construction, `:cwd`, and `no_session_persistence` at [claude_test.exs:22-61](integrations/claude/test/gen_agent/backends/claude_test.exs:22); there are no tests for invalid enums, malformed shapes, or unknown keys.

### Already resolved or changed

- The old review’s `claude_wrapper 0.14.4` reference is stale: this checkout locks **0.14.5** in [mix.lock](integrations/claude/mix.lock:3). The wrapper source is not present in this checkout, so the old line-level wrapper trace cannot be re-confirmed here.
- The README now documents ignored unknown keys and malformed tool-list options, along with the option shapes and permission modes. That resolves the documentation omission, **not** the runtime behavior.
- Existing behavior for `:cwd`, `:stream_fn`, and core callback compatibility is implemented at [claude.ex:67-68](integrations/claude/lib/gen_agent/backends/claude.ex:67), [claude.ex:130-137](integrations/claude/lib/gen_agent/backends/claude.ex:130), and [claude.ex:83-88](integrations/claude/lib/gen_agent/backends/claude.ex:83). A fix should preserve these.

### Smallest change plan

1. **`integrations/claude/lib/gen_agent/backends/claude.ex`**: add start-time option validation before constructing the session. Check supported keys (including documented wrapper options and backend-only `:stream_fn`, `:cwd` alias, and explicitly handled session options), validate the reported list and binary shapes, and validate enum values. Return a stable `{:error, ...}` tuple naming the invalid key/value. Keep `resume_session/2` routed through this validation.
2. **`integrations/claude/test/gen_agent/backends/claude_test.exs`**: add provider-free tests for invalid `:permission_mode` and `:effort`, non-binary `:json_schema`, malformed tool/list options, and misspelled or unsupported keys. Assert errors come from both `start_session/1` and `resume_session/2` as appropriate, while valid aliases and `:stream_fn` injection continue to work.

I did not edit files.
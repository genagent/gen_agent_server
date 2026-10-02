I’ll compare the adapter and tests with the locked wrapper, checking option compatibility, validation behavior, and scope.


The allowlist covers every key in the locked wrapper’s `apply_opt` clauses. I found a compatibility issue in the value checks: the wrapper supports `ClaudeWrapper.ToolPattern` entries in allowed/disallowed tool lists, but the new validator rejects them. I’m also checking whether malformed environment values reliably return error tuples.


REQUEST CHANGES

- **P2 — `integrations/claude/lib/gen_agent/backends/claude.ex:239`: Valid tool patterns are rejected.** Locked wrapper 0.14.5 supports `%ClaudeWrapper.ToolPattern{}` entries in `:allowed_tools` and `:disallowed_tools`. The binary-only check breaks that compatibility. Accept patterns with binary values and add positive tests. Provider-free probes confirmed the wrapper builds valid flags while the adapter rejects both options.

- **P2 — `integrations/claude/lib/gen_agent/backends/claude.ex:247`: Malformed environment values can raise instead of returning an error tuple.** Structs satisfy `is_map/1`, but generally do not implement `Enumerable`. `Claude.start_session(env: URI.parse("https://example.com"))` raises `Protocol.UndefinedError`. Reject unsupported structs before enumeration and add a regression test.

- **P3 — `integrations/claude/README.md:165`: The documented allowlist is inaccurate.** “A key not listed below” supposedly returns `:unknown_option`, but accepted keys including `:settings`, `:files`, and `:plugin_dirs` are absent. Restore the “commonly used options” qualification and reference the complete supported surface.

Validation: compiled the changed adapter in memory and ran `claude_test.exs` against existing dependency beams: **21 passed**. Mix checks were not run. Changes are confined to `integrations/claude`.
I’ll compare the changes with the locked wrapper’s source and the adapter’s documented options, then check the tests and scope.


I found the locked `claude_wrapper` 0.14.5 package in the local Hex cache. The new allowlist rejects several supported wrapper options and `no_session_persistence: false`, which an existing test requires. I’m checking environment validation and the claim that `nil` is treated as unset.


REQUEST CHANGES

- **[P2] Valid environment options are rejected; malformed ones pass.** `integrations/claude/lib/gen_agent/backends/claude.ex:202` rejects `env: [{"FOO", "bar"}]`, the format documented by locked `ClaudeWrapper.Config`. Conversely, `env: %{"FOO" => %{}}` passes validation but fails when the runner converts values to charlists. Validate environment entries against the wrapper’s supported shapes and add regression tests for both cases.

- **[P2] Explicitly enabled session persistence now fails.** `integrations/claude/lib/gen_agent/backends/claude.ex:167` omits `:no_session_persistence` from known options. Consequently, `no_session_persistence: false` returns `{:error, {:unknown_option, :no_session_persistence}}`. This breaks the existing test at `integrations/claude/test/gen_agent/backends/claude_test.exs:27`. Preserve acceptance of `false` while rejecting `true`.

- **[P2] The allowlist removes supported wrapper options.** `integrations/claude/lib/gen_agent/backends/claude.ex:141–180` rejects options recognized by locked 0.14.5, including `:settings`, `:append_system_prompt_file`, `:permission_prompt_tool`, and `:exclude_dynamic_system_prompt_sections`. It also rejects the documented `binary: :bundled`. Derive validation from the locked Config and Query implementations and test supported values; the README’s previous list was explicitly non-exhaustive.

I ran the adapter unit test file using in-memory compilation and the cached wrapper’s `StreamEvent`: **18 passed, 1 failed**. This was not a full Mix suite run. The diff stays within `integrations/claude`.
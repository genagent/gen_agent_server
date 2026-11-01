Implement the breaking change “inherit the creator’s tools and permissions by default” in the current gen_agent_server worktree.

Work only in the current directory, `/Users/joshrotenberg/Code/github.com/genagent/gen_agent_server-137`. Do not run git commands that change history, branches, or remotes. Follow repository instructions and existing conventions. Do not use Due or its reporting/A/B workflow. Do not delegate recursively.

The implementation sandbox is Codex `workspace_write` with no network. Run every Mix command with `MIX_OS_CONCURRENCY_LOCK=0`. Tests that inspect OS processes or open sockets fail in this sandbox; the host run is authoritative. Run the required checks anyway and report exact failures without claiming a passing host run.

Implement these changes, using the following current line references as starting points. Line numbers will shift after edits.

- `lib/gen_agent_server/providers.ex`
  - Update moduledoc lines 6-11 and option documentation lines 35-39.
  - In `build_opts("claude", opts)` at lines 88-95, accept `:inherit`, `:read_only`, `:plan`, `:accept_edits`, `:auto`, `:bypass_permissions`, and `:dont_ask`, defaulting to `:inherit`.
  - `choice/3` at lines 151-153 selects the first allowed value as the default. Preserve its fixed allowlist validation.
  - Extend `claude_access_opts/1` at lines 126-129 with `:inherit -> []`. Preserve `:read_only -> [permission_mode: :dont_ask, tools: ["Read", "Grep", "Glob"]]`. Other explicit modes pass their matching atom as `:permission_mode`, without adding a tools restriction.
  - In `build_opts("codex", opts)` at lines 98-120, default both `:codex_sandbox` and `:codex_user_config` to `:inherit`. Accept sandbox values `:inherit`, `:read_only`, and `:workspace_write`. Omit the backend `:sandbox` key when inherited; never pass `sandbox: :inherit`. Include `ignore_user_config: true` only for explicit `:ignore`.
  - Retain `approval_policy: :never`, response-text defaults, model/effort behavior, trusted provider overrides, and child-environment hardening.
  - The existing dependencies support omission and the requested explicit Claude modes. Do not edit dependencies. `deps/gen_agent_claude/lib/gen_agent/backends/claude.ex:164` accepts the modes. `deps/claude_wrapper/lib/claude_wrapper/query.ex:1431-1437` maps atoms to CLI spellings: `auto`, `bypassPermissions`, `dontAsk`, `plan`, and `acceptEdits`.
  - Codex fresh/resumed option builders are in `deps/gen_agent_codex/lib/gen_agent/backends/codex.ex:313-329` and `365-378`. Resumed sandbox settings become `sandbox_mode` config overrides. Inheritance must omit that override as well as fresh-turn `--sandbox`.

- `lib/gen_agent_server/instance_spec.ex`
  - Update the default/access documentation at lines 19-33.
  - Update `@choices` at lines 44-48 to default Claude mode, Codex sandbox, and Codex user config to `:inherit`, with the allowlists above.
  - Preserve `route_choices/3` at lines 211-229, which converts only fixed allowed strings to atoms and supplies defaults.
  - Preserve description construction in `route/3` at lines 121-134 and option forwarding at lines 232-243. Configured descriptions must report `inherit` explicitly.
  - Preserve `explicit_review_read_only?/2` at lines 140-147: only an explicitly supplied `read_only` value establishes review provenance.

- `lib/gen_agent_server/profiles.ex`
  - Update the moduledoc at lines 2-7.
  - Change defaults at lines 59-62 to `"inherit"` for both providers’ access settings and Codex user config.
  - Update allowlists at lines 64-77. Profiles currently reject Claude `read_only`; accept it alongside the new modes.
  - Preserve provider-specific field checks at lines 80-93 and fixed validated atom conversion/`Providers.backend_opts/2` construction at lines 96-107.

- `lib/gen_agent_server/runtime_config.ex`
  - Update startup option construction in `agent/2` at lines 59-84 so default Claude options omit permission mode/tools, and default Codex options omit sandbox/ignore-user-config while retaining approvals disabled.
  - Prefer reusing `Providers.backend_opts/2` to keep startup defaults aligned with profiles and dynamic routes. Preserve the existing unknown-provider `ArgumentError`, cwd validation, agent tuple shape, and release child-environment cleanup. Avoid adding startup configuration variables.
  - Document inherited access and headless prompt limitations in the moduledoc.

- `lib/gen_agent_server/ops.ex`
  - Update access enums in `config_schema/0` at lines 337-342 to match the parser.
  - Document inheritance defaults in those properties.
  - No new operation is required.

- `extensions/patterns/lib/gen_agent_server/pattern_spec.ex`
  - Update access documentation at lines 58-63.
  - Update `provider_options/2` at lines 148-168 to accept sandbox `inherit` and all supported Claude modes, including `read_only`.
  - Preserve `edit_mode/4` validation at lines 172-181 and provider-option forwarding through `Providers.backend_opts/2` at lines 226-243.

- Tests
  - Add focused provider-option coverage for omitted options, explicit inheritance, every explicit access mode, explicit Codex config ignore/inherit, and invalid values. Keep application overrides isolated and restored using existing patterns.
  - Update profile coverage in `test/gen_agent_server_test.exs:300-384`; add omitted-default and newly accepted mode cases.
  - Add direct `RuntimeConfig.from_env!/1` coverage for the three providers, defaults, invalid providers, and consistency with shared provider defaults.
  - Update `test/gen_agent_server_lifecycle_test.exs`, particularly default descriptions/backend capture at lines 109-138 and fresh/resumed Codex coverage at lines 324-385. Assert inheritance omits sandbox and user-config overrides on both turns while retaining `approval_policy="never"`. Preserve model and effort assertions.
  - Cover explicit narrowing configurations independently. Explicit `workspace_write` no longer implies ignored user config; specify `codex_user_config: ignore` when testing the complete old configuration.
  - Assert operation schema enums and dynamic `describe_instance` access values, including all new modes.
  - Update `extensions/patterns/test/gen_agent_server_run_test.exs`, including existing defaults at lines 21-41 and spec cases near lines 134-164.
  - Update relevant expectations in `extensions/mcp/test/gen_agent_server_mcp_lifecycle_test.exs`.
  - Extend review-route cases in `extensions/control/test/gen_agent_server_control_controller_test.exs:336-344` for inheritance and new Claude modes. Preserve `extensions/control/lib/gen_agent_server/control/controller.ex:294-310`: only Echo or explicitly read-only Claude/Codex routes qualify.
  - Explicit `permission_mode: :plan` fixtures in `test/gen_agent_server_child_env_test.exs:168-214` test hardening of supplied options, not defaults. Preserve that coverage.

- Documentation
  - Update `README.md:39-41`, `151-171`, and relevant dynamic-route descriptions.
  - Update `extensions/mcp/README.md:111-113` and guides in `extensions/mcp/lib/gen_agent_server/mcp/resources.ex:101-106` and `237-240`.
  - Update pattern access documentation and any remaining contradictory default statements.
  - Explain that inheritance omits server overrides and uses the server process user’s CLI settings. It does not transfer transient client permissions automatically. Explicit Claude modes support callers that know their mode.
  - Explain that headless sessions cannot answer prompts; Codex retains approvals disabled. Access still depends on CLI configuration and host permissions.
  - Preserve the unconfigured-instance contract documented in `lib/gen_agent_server.ex:68-75` and implemented in `lib/gen_agent_server/invocations.ex:133-142`: profile/startup instances report route names only. Do not expose their backend options or attempt to read user configuration to discover effective permissions.

Corrected acceptance list:

- A route with omitted access options produces no backend sandbox, permission-mode, tools, or ignore-user-config override. Codex retains `approval_policy: :never`.
- Explicit `inherit` behaves like omission.
- Explicit narrowing values preserve their individual mappings. Reproducing the previous complete Codex options requires explicit `codex_user_config: ignore`.
- Claude `auto`, `bypass_permissions`, and `dont_ask` produce the corresponding CLI permission modes without the read-only tools restriction.
- Profiles, dynamic routes, startup agents, and pattern-created agents share inheritance defaults; applicable parsers accept the supported values.
- Configured dynamic `describe_instance` responses report selected access values, including `inherit`; operation schemas list all supported values. Unconfigured instances retain their existing names-only description.
- Explicit read-only review provenance and control review admission remain intact.
- Formatting, warnings-as-errors compilation, root tests, and all extension tests pass on the authoritative host, with sandbox failures accurately reported.

Before finishing, run these exact checks, attempting every test project even if another fails:

```sh
MIX_OS_CONCURRENCY_LOCK=0 mix format
MIX_OS_CONCURRENCY_LOCK=0 mix compile --warnings-as-errors
MIX_OS_CONCURRENCY_LOCK=0 mix test
(cd extensions/control && MIX_OS_CONCURRENCY_LOCK=0 mix test)
(cd extensions/mcp && MIX_OS_CONCURRENCY_LOCK=0 mix test)
(cd extensions/patterns && MIX_OS_CONCURRENCY_LOCK=0 mix test)
(cd extensions/peers && MIX_OS_CONCURRENCY_LOCK=0 mix test)
(cd extensions/public_source && MIX_OS_CONCURRENCY_LOCK=0 mix test)
(cd extensions/schedule && MIX_OS_CONCURRENCY_LOCK=0 mix test)
(cd extensions/selection && MIX_OS_CONCURRENCY_LOCK=0 mix test)
```

Finish with a summary of files changed, API added or expanded, tests added, the exact check commands run with results, and anything not done with the reason.

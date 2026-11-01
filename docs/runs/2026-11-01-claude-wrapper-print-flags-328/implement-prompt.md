Implement issue #328 in the current worktree of `claude_wrapper`, an Elixir wrapper for the Claude Code CLI.

Work only in `/Users/joshrotenberg/Code/github.com/genagent/claude_wrapper_ex-328`. Do not run git commands that change history, branches or remotes. Follow repository AGENTS.md, CLAUDE.md and existing conventions. Do not use Due or recursively delegate. Do not add runtime dependencies.

CLI findings from read-only triage:

- `claude --version` returned `2.1.316 (Claude Code)`.
- `claude --help` exited 0. All visible flags requested below remain present, with the issue’s enum choices unchanged.
- Permission-mode help lists `acceptEdits`, `auto`, `bypassPermissions`, `manual`, `dontAsk`, `plan`. Preserve `:default -> "default"` for compatibility. The issue reports acceptance on 2.1.305, 2.1.311 and 2.1.312; triage did not validate that value on 2.1.316.
- Missing-operand probes confirmed recognition of all three hidden flags on 2.1.316. Each exited 1 with its own `argument missing` error.
- Autocompact help specifies `auto` or 100k–1M tokens. Use integer token counts from 100,000 through 1,000,000 in the typed API, rather than unrestricted positive integers.
- Snapshot help says `on` reuses the recorded prompt until compaction, with a default exception under `--bare` outside cloud and background sessions. `off` renders the prompt fresh.
- Other print-capable flags absent from the issue’s table, including include-hook-events, bare, brief, safe-mode, plugin-url and exclude-dynamic-system-prompt-sections, already have Query support. Do not duplicate them or claim they were introduced after 2.1.312.

Implement file by file, using these current pre-change references:

1. `lib/claude_wrapper/query.ex`
   - Extend the permission-mode type at line 40, query type starting at line 49 and struct at line 104.
   - Follow existing setters such as `system_prompt/2` at lines 175–176, `append_system_prompt_file/2` at lines 187–189 and `permission_mode/2` at lines 208–209.
   - Add documented and specified setters and matching keyword options:
     - `restricted/1`, `restricted: true`, emitting `--restricted`.
     - `permission_prompts/2`, `:host | :none`, emitting `--permission-prompts`.
     - `system_prompt_snapshot/2`, `:on | :off`, emitting `--system-prompt-snapshot`.
     - `autocompact/2`, `:auto | integer()` within 100,000–1,000,000, emitting `auto` or decimal tokens.
     - `allow_dangerously_skip_permissions/1`, emitting `--allow-dangerously-skip-permissions`. Document that it makes bypass available without enabling bypass. Preserve the existing DangerousClient gate.
     - `chrome/2`, with `nil` as the unset field default, true emitting `--chrome` and false emitting `--no-chrome`.
     - `forward_subagent_text/1`, emitting `--forward-subagent-text`. Document that it requires print mode with stream-json output. `Query.stream/2` at line 1356 already forces stream-json.
     - `append_subagent_system_prompt/2`, `append_subagent_system_prompt_file/2` and `advisor/2`, emitting their matching hidden value flags.
     - `extra_args/2`, accepting a list of strings and preserving argument order and token boundaries.
   - Preserve existing `prompt_suggestions/1` at line 394. Add `prompt_suggestions/2`, change the field/type to `nil | boolean()`, and use nil for unset. True should retain bare-flag behavior; false must emit `["--prompt-suggestions", "false"]`.
   - Update keyword routing: `apply_opts/2` at line 518, `@value_opts` at line 523, `@bool_opts` at line 553, `@list_opts` at line 571, `@known_opts` at line 582 and `apply_opt/2` at lines 606–637. Handle Chrome and prompt suggestions separately from the generic false-skipping boolean path. Give extra_args a validated list path rather than the generic single-string list shorthand.
   - Extend `build_args/1` at lines 1534–1593 using its existing emission helpers. Append extra_args immediately before `append_prompt/2`; the separator helper is at lines 1639–1640. Preserve prompt delivery through both stdin and argv.
   - Extend `format_permission_mode/1` at lines 1674–1689 with `:manual -> "manual"` and update its allowed-values error. Keep `permission_mode_arg/1` at line 1672 as the shared mapping.
   - Use `invalid_enum!/3` at line 1708 for invalid enum values. Follow existing validation timing and error style. Reject malformed autocompact and extra_args values with clear `ArgumentError`s.
   - `spawn_args/1` at line 1485 already reuses build_args and strips duplex-owned transport settings. Ensure the new flags survive this path.

2. `lib/claude_wrapper/session.ex`
   - `new/2` options documentation is at lines 42–57.
   - `send/3` documentation starts at line 69.
   - `build_query/3` at lines 230–253 merges session options with per-call overrides, applies Query options and threads the established resume ID.
   - Document `system_prompt_snapshot: :off` for changing a resumed turn’s system prompt. Preserve default CLI behavior when unset. Existing generic routing should require no special session state or snapshot implementation.

3. `lib/claude_wrapper/duplex_session.ex`
   - Option documentation around line 356 describes the existing extra_args escape hatch.
   - `open_session/2` at lines 927–949 obtains `Query.spawn_args/1` from `:query`, then appends explicit duplex extra_args.
   - Expose forwarding through the existing `query: %Query{}` mechanism and document an example using `Query.forward_subagent_text/1`. Avoid adding a parallel option-routing system.
   - `set_permission_mode/3` at lines 619–622 already calls `Query.permission_mode_arg/1`; verify `:manual` reaches its control request unchanged.

4. `lib/mix/tasks/claude.contract.ex`
   - Add the three hidden value flags to `@hidden_value_flags` at line 38.
   - Preserve the missing-operand recognition probe `recognized_hidden?/2` at lines 100–105.
   - Extend `maximal_query/0` at lines 163–215 and `specs/0` at line 218 so every new named flag is exercised. Add separate specimens where necessary, particularly `--chrome` and `--no-chrome`.
   - The task checks flag names, not full CLI value or combination semantics. Do not describe its success as runtime validation.

5. Tests
   - Extend `test/claude_wrapper/query_test.exs`: keyword routing tests begin at line 22, prompt separator tests at line 342, permission enum tests at line 357, spawn_args coverage around line 464 and hidden-flag tests at line 611.
   - Cover every new setter and keyword route, exact emitted operands, unset omission, explicit false, invalid enums, autocompact boundaries, malformed extra_args and argument placement before `--`.
   - Preserve existing prompt-suggestion tests in `test/claude_wrapper_test.exs` around lines 301–348.
   - Follow `test/claude_wrapper/session_selector_test.exs`, especially its two-turn fake CLI helper at lines 9–27, for a regression showing turn two includes the established `--resume`, a changed `--system-prompt` and `--system-prompt-snapshot off`. Test per-call override precedence. Extend the fixture only if needed.
   - Add DuplexSession coverage using existing fake-process patterns in `test/claude_wrapper/duplex_session_test.exs`. Verify Query spawn propagation of forwarding.
   - Extend permission control coverage in `test/claude_wrapper/duplex_session/control_test.exs` around lines 620–691 for `:manual`.
   - Extend `test/mix/tasks/claude_contract_test.exs`, following the hidden-option test at line 25, to cover all three added hidden probes and rejection of unrecognized flags.
   - Keep live CLI tests tagged `:integration`. Fake argv tests cannot prove which system prompt the real CLI sends to the API. If adding request-body validation, use an isolated local server and disposable state without real credentials, billing or user conversation data.

6. Documentation
   - Update the Query section of `README.md` around line 174 and relevant public docs in `lib/claude_wrapper.ex` around lines 183–200.
   - Explain the new options, prompt-suggestion false behavior, extra_args ordering, stream-json forwarding restriction and snapshot behavior.
   - Name version provenance accurately: issue evidence covers 2.1.305, 2.1.311 and 2.1.312; triage checked help and hidden-flag recognition on installed 2.1.316.
   - List these launch flags as out of scope: `--ax-screen-reader`, `--bg`/`--background`, `--cloud`, `--desktop`, `--environment`, `--ide`, `--remote-control`, `--remote-control-session-name-prefix`, `--teleport`.
   - `Config.base_args/1` is now at lines 187–192 and needs no change.

Acceptance checklist:

- Every newly requested option has a typed struct field, documented setter, keyword route and argv emission. Existing permission_mode and prompt_suggestions fields are extended rather than duplicated. Enum errors use `invalid_enum!/3`.
- Unset prompt suggestions emit nothing; true retains the bare flag; false emits `--prompt-suggestions false`.
- Chrome is unset by default and supports both explicit boolean spellings.
- Autocompact accepts `:auto` or integer token counts within 100,000–1,000,000 and rejects unsupported values.
- `:manual` emits `manual`, including through DuplexSession’s shared control mapping; `:default` still emits `default`.
- Forward-subagent text is documented as requiring print plus stream-json and propagates through streaming and the DuplexSession Query bridge.
- A resumed Session turn can pass its changed system prompt together with snapshot off. Distinguish argv regression coverage from real request-body verification.
- All three hidden flags are contract-probed and exercised by contract specimens. Run `mix claude.contract` on installed 2.1.316. Compatibility with 2.1.312 remains a target; report it as unverified unless that version is actually available and tested.
- Query extra_args accepts only a list of strings, preserves order and appears before the prompt separator.
- Documentation includes the complete out-of-scope list.

Before finishing, run `mix format`, `mix compile --warnings-as-errors`, `mix credo --strict` and `mix test`. Also run `mix claude.contract`. Report the exact commands and their results, including failures or environment limitations. Follow any additional applicable repository checks without claiming checks you did not run.

Finish with a summary of files changed, API added, tests added and anything not done with its reason.

You are reviewing an uncommitted change in this worktree of claude_wrapper, an Elixir wrapper for the Claude Code CLI, before it is committed. Read it with git diff and git status, and read any file. Do not edit files.

The operator already ran on the host: compile with warnings as errors, format, mix test (1030 passed, 1004 before), dialyzer, docs, and mix claude.contract on Claude Code 2.1.316 (no drift). All pass except mix credo --strict, which reports one warning: lib/claude_wrapper/query.ex:125, struct has more than 56 fields (64 found), from the max_fields setting in .credo.exs.

Review the change against the issue below. Report:
1. For each acceptance item: met, not met, or not verifiable, with the file and line that shows it.
2. Defects: incorrect behaviour, missing cases, API inconsistencies with the surrounding code, doc claims the code does not support. For each: file:line, what is wrong, a concrete fix.
3. Anything in the diff the issue did not ask for, and whether it should stay.
4. A verdict on the last line: APPROVE or REQUEST CHANGES.

Report only what you can point to in the code. Do not restate the change.

# Issue: feat(query): expose --restricted, --permission-prompts, --system-prompt-snapshot and the other 2.1.312 print flags Query lacks

`claude --help` in Claude Code 2.1.312 lists eight print-mode flags that `ClaudeWrapper.Query` cannot emit, and two that it maps only in part. The typed one-shot surfaces (`ClaudeWrapper.query/2`, `ClaudeWrapper.stream/2`, `Query`, `Session`) have no way to add a flag; the only routes today are `ClaudeWrapper.raw/2` (raw argv, unparsed stdout) and the `:extra_args` option of `DuplexSession`. The visible flag set is the same in 2.1.305, 2.1.311 and 2.1.312, and every flag below passed argument validation on 2.1.312.

| Claude Code 2.1.312 flag | Before (claude_wrapper 0.17.0) | After |
|---|---|---|
| `--restricted`: removes the code-running tools and WebFetch unless `--tools` names them, ignores user, project and local settings files, confines file tools to the working directories, refuses bypassPermissions | not reachable from typed one-shot calls | `Query.restricted/1`, `restricted: true` |
| `--permission-prompts <host\|none>`: `none` denies anything that would prompt | not reachable | `Query.permission_prompts/2`, `permission_prompts: :host \| :none` |
| `--system-prompt-snapshot <on\|off>`: with `on` (the default) a resumed conversation keeps sending the first recorded system prompt | not reachable; a resumed turn (every `Session` turn after the first) that passes a new `--system-prompt` still sends the first one (see Evidence) | `system_prompt_snapshot: :on \| :off` |
| `--autocompact <auto\|tokens>` | not reachable | `autocompact: :auto \| pos_integer()` |
| `--allow-dangerously-skip-permissions` | not reachable | `allow_dangerously_skip_permissions: true` |
| `--chrome`, `--no-chrome` | not reachable | `chrome: true \| false` |
| `--forward-subagent-text` (stream-json only) | not reachable | `forward_subagent_text: true` for `stream/2` and `DuplexSession` |
| `--prompt-suggestions [value]` | `true` emits the bare flag; `false` emits nothing, so a settings-enabled value cannot be turned off | `false` emits `--prompt-suggestions false` |
| `--permission-mode manual` | no `:manual`; `:default` emits `default`, which help no longer lists but 2.1.305, 2.1.311 and 2.1.312 still accept | `:manual` emits `manual`; `:default` unchanged |
| Hidden from 2.1.312 help: `--append-subagent-system-prompt <prompt>`, `--append-subagent-system-prompt-file <file>`, `--advisor <model>` | not reachable | setters, checked by the contract's hidden-flag probe |
| Any later flag | no typed escape hatch | `extra_args: [String.t()]` on `Query`, placed before the `--` prompt separator |

## API sketch

```elixir
Query.new("audit lib/")
|> Query.restricted()
|> Query.permission_prompts(:none)
|> Query.system_prompt_snapshot(:off)
|> Query.autocompact(500_000)
|> Query.permission_mode(:manual)

ClaudeWrapper.query("audit lib/",
  restricted: true,
  permission_prompts: :none,
  append_subagent_system_prompt: "Report findings only.",
  extra_args: ["--new-flag", "value"]
)
```

## Acceptance

- [ ] Each flag in the table has a struct field, a setter, an `apply_opt` clause and a `build_args/1` emission; enum values go through `invalid_enum!/3`.
- [ ] `prompt_suggestions: false` emits `--prompt-suggestions false`; unset emits nothing.
- [ ] `:manual` emits `manual` and `:default` still emits `default`; the docs name the CLI versions checked. #302 (merged 2026-10-29) reuses this mapping for `DuplexSession.set_permission_mode/2` (`Query.permission_mode_arg/1`).
- [ ] `forward_subagent_text` is documented as stream-json only (with `--output-format json`, 2.1.312 exits 1 with `Error: --forward-subagent-text requires --print and --output-format=stream-json.`).
- [ ] `system_prompt_snapshot: :off` on a `Session` turn sends that turn's `system_prompt`.
- [ ] `mix claude.contract` passes on 2.1.312 with the three hidden flags added to `@hidden_value_flags` (lib/mix/tasks/claude.contract.ex:38).
- [ ] The docs list the interactive, cloud and background flags as out of scope: `--ax-screen-reader`, `--bg`/`--background`, `--cloud`, `--desktop`, `--environment`, `--ide`, `--remote-control`, `--remote-control-session-name-prefix`, `--teleport`.

## Evidence

claude_wrapper 0.17.0 (22b849d), Claude Code 2.1.312 (help also diffed against 2.1.305 and 2.1.311), Elixir 1.20.4 / OTP 29, macOS arm64.

- `lib/claude_wrapper/query.ex:1312-1370` (`build_args/1`) and `lib/claude_wrapper/config.ex:161-166` (`base_args/1`) emit none of the flags above. `prompt_suggestions/1` only sets `true` (query.ex:389, emitted at :1360). `permission_mode` atoms are listed at query.ex:39-40 and mapped at :1431-1444. `lib/claude_wrapper/duplex_session.ex:251-253` documents `:extra_args` as "the escape hatch for flags not yet on `Query`"; no one-shot equivalent exists.
- The 2.1.312 binary defines the three hidden flags with `.hideHelp()`; its permission-mode parser accepts `["acceptEdits","auto","bypassPermissions","default","dontAsk","plan","manual"]` and prints the list with `default` replaced by `manual`.
- Argument checks ran with `env -i`, a fake HOME, a dummy API key, `CLAUDE_CODE_MAX_RETRIES=0` and `ANTHROPIC_BASE_URL=http://127.0.0.1:9` (nothing listening), so a run that passes validation stops at the network:

```text
claude -p --no-session-persistence --output-format json --permission-mode default -- hi
  exit 1, result "API Error: Connection refused ... (ECONNREFUSED)"; stream-json init "permissionMode":"default"
claude -p --no-session-persistence --output-format json --permission-mode manual -- hi
  exit 1, same network error; stream-json init "permissionMode":"default"
claude -p --no-session-persistence --output-format json --permission-mode bogus -- hi
  error: option '--permission-mode <mode>' argument 'bogus' is invalid. Allowed choices are acceptEdits, auto, bypassPermissions, manual, dontAsk, plan.
--system-prompt-snapshot off, --autocompact auto, --permission-prompts none, --allow-dangerously-skip-permissions,
--restricted, --chrome, --no-chrome, --prompt-suggestions false, --append-subagent-system-prompt x,
--append-subagent-system-prompt-file f, --advisor opus, --forward-subagent-text (stream-json)
  each reached the network error
--system-prompt-snapshot maybe   -> Allowed choices are on, off.
--permission-prompts nobody      -> Allowed choices are host, none.
--autocompact 5k                 -> It must be 'auto', or between 100k and 1M (e.g. 500k, 200000, or 200 as shorthand)
--prompt-suggestions maybe       -> Allowed choices are true, false, 1, 0, yes, no, on, off.
```

- Snapshot, with `ANTHROPIC_BASE_URL` pointed at a local server that records request bodies and answers 400: `claude -p --system-prompt "SP_ONE"` then `claude -p --resume <id> --system-prompt "SP_TWO"` sent `SP_ONE`; adding `--system-prompt-snapshot off` to the resume sent `SP_TWO`.

## Related

- #222 (the previous batch of one-shot flags)
- #220 (enum values raise `ArgumentError`)
- #289 and PR #294 (the 2.1.309 contract task, which checks flag names but not values)

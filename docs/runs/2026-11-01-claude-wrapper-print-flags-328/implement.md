I've implemented #328, but none of it has been compiled or run. Every Bash command in this session was refused with "This command requires approval", including `git status`, `mix compile` and `mix format`, so I couldn't run any of the checks. Nothing is committed.

## Checks

| Command | Result |
|---|---|
| `mix format` | Not run (Bash refused) |
| `mix compile --warnings-as-errors` | Not run |
| `mix credo --strict` | Not run |
| `mix test` | Not run |
| `mix claude.contract` | Not run, so I haven't verified anything on 2.1.316 myself. 2.1.312 compatibility is also unverified. |
| `mix dialyzer`, `mix docs --warnings-as-errors` | Not run |

I made a few layout fixes by hand where I could predict the formatter's output. `mix format` may still change some test-file layout.

## Files changed
- `lib/claude_wrapper/query.ex`
- `lib/claude_wrapper/session.ex` (docs only)
- `lib/claude_wrapper/duplex_session.ex` (docs only)
- `lib/mix/tasks/claude.contract.ex`
- `lib/claude_wrapper.ex` (docs)
- `README.md`
- Tests: `query_test.exs`, `session_selector_test.exs`, `duplex_session_test.exs`, `duplex_session/control_test.exs`, `mix/tasks/claude_contract_test.exs`

## API added (`Query`)
- **New setters and keyword options:** `restricted/1`, `permission_prompts/2` (`:host | :none`), `system_prompt_snapshot/2` (`:on | :off`), `autocompact/2`, `allow_dangerously_skip_permissions/1`, `chrome/2`, `forward_subagent_text/1`, `append_subagent_system_prompt/2`, `append_subagent_system_prompt_file/2`, `advisor/2`, `extra_args/2`.
- **Prompt suggestions:** added `prompt_suggestions/2`. The field is now `nil` when unset and emits nothing. `true` emits the bare flag; `false` emits `--prompt-suggestions false`.
- **Behaviour change:** `prompt_suggestions: false` in `apply_opts/2` used to do nothing. It now emits `--prompt-suggestions false`, which the issue asked for. `chrome` works the same way, and `nil` leaves either one unset.
- **Autocompact:** accepts `:auto` or an integer from 100,000 through 1,000,000. Anything else raises `ArgumentError` when the argv is built.
- **New enums:** invalid values raise through `invalid_enum!/3` when the argv is built, like `effort`.
- **`permission_mode(:manual)`:** emits `manual`, and `:default` still emits `default`. `DuplexSession.set_permission_mode/3` shares the same mapping.
- **`extra_args`:** only a list of strings is accepted, and calls add to the list in order. The values go after every other flag and just before `--`, so prompts still go through stdin or argv. A `"--"` element is rejected; that rule is my addition, because it would end option parsing early. The list is checked both in the setter and when the argv is built.
- **DangerousClient:** unchanged. `allow_dangerously_skip_permissions` never emits `--dangerously-skip-permissions`.
- **Contract task:** the three hidden flags are added to the probe list. The maximal query now covers every new flag, and a separate specimen covers `--no-chrome` and `--prompt-suggestions false`. I exposed `hidden_value_flags/0`, `alternate_queries/0` and `query_specs/0` as `@doc false` helpers for tests. The task still checks flag names only.

## Tests added
- **Query:**
  - every setter and keyword option, with the exact argv emitted
  - nothing emitted when unset
  - explicit false for chrome and prompt suggestions
  - invalid enums
  - autocompact edge values (99,999, 100,000, 1,000,000 and 1,000,001), plus bad types
  - `:manual`
  - the new flags passing through `spawn_args`
  - `extra_args` order, token boundaries, placement before `--`, and rejection of bad input
  - an end-to-end check against a fake CLI that the prompt still arrives through stdin and through argv
- **Session:** turn two sends `--resume fake-session`, the changed `--system-prompt` and `--system-prompt-snapshot off`. A per-call option overrides the session's setting, and nothing is emitted when unset. This only checks the argv; it doesn't prove which system prompt the real CLI sends to the API.
- **DuplexSession:** forwarding, `:manual`, snapshot and `--no-chrome` reach the spawn args through `query:`. The query's `extra_args` come before the session's own.
- **Control:** `set_permission_mode` sends `manual` and `default` on the wire.
- **Contract:** each of the three hidden flags passes the missing-operand probe, an unrecognized one fails, and the specimens cover every new flag.

## Not done
- **All checks:** blocked by Bash approval. Please run the commands in the table above and send me any failures.
- **Request-body verification:** I didn't add a local-server check of what the real CLI sends.
- **CHANGELOG:** not edited, since release-please generates it.
- **Wording:** the docs for `restricted/1` and `advisor/2` stay neutral because I didn't confirm what those flags do. `forward_subagent_text` is documented as possibly rejected by `execute/2` (JSON output). That's my reading of the stream-json requirement, not something I tested.

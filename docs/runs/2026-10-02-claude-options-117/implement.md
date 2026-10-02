All three findings hold. I changed `claude.ex` and `claude_test.exs`, both under `integrations/claude`. I haven't run Mix or any tests.

- **Env validation (fixed):** `env` now accepts a map or a list of `{name, value}` tuples, so `[{"KEY", "value"}]` passes. Names must be strings or atoms. Values must be strings, or `false` to unset the variable. `%{"FOO" => %{}}`, `[{"FOO", 1}]`, `["FOO=bar"]`, `[{1, "x"}]` and `"FOO=bar"` return `{:invalid_option, :env, bad}`. This matches how the locked wrapper's port runner converts env.
- **`no_session_persistence: false` (fixed):** `:no_session_persistence` is now a known boolean key. `true` is still rejected earlier with `:unsupported_option`. That should make the existing test at line 27 pass.
- **Missing allowlist keys (fixed):** I compared against every `apply_opt` key in the locked `claude_wrapper` 0.14.5 `Query`, plus Config's `binary`, `working_dir`, `env`, `timeout`, `verbose` and `debug`. These keys were added:
  - strings: `settings`, `append_system_prompt_file`, `permission_prompt_tool`, `agents_json`, `from_pr`, `debug_filter`, `debug_file`, `name`
  - lists: `files`, `plugin_dirs`, `plugin_urls`
  - string or list: `betas`
  - `max_thinking_tokens`, `input_format`
  - `worktree` (boolean or string)
  - booleans: `fork_session`, `tmux`, `prompt_suggestions`, `replay_user_messages`, `bare`, `disable_slash_commands`, `include_hook_events`, `safe_mode`, `exclude_dynamic_system_prompt_sections`
  - `binary` now accepts a string or `:bundled`.

  I also tightened `output_format` to `:text`, `:json` or `:stream_json`, because the wrapper raises on anything else, including strings. The moduledoc is updated.

I added two tests: one positive compatibility test covering all the keys above, and one for malformed env contents.
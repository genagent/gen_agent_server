I've finished reading the change. The code meets the issue. I'm requesting changes for three reasons: the doc rewrites deleted unrelated documentation, the new default weakens the control extension's read-only review check for Codex without saying so, and the same seven-value list is now hand-copied into five files.

## 1. Acceptance items

| Item | Status | Evidence |
| --- | --- | --- |
| A route with no access option has no sandbox, permission-mode or tools override, and Codex user config is inherited | Met | `lib/gen_agent_server/providers.ex:91-101,109-122,135`. The first value in each `choice/3` list is the default (`providers.ex:162`), and it is `:inherit` everywhere. `InstanceSpec` uses the same rule (`instance_spec.ex:224-229`). Tested in `test/gen_agent_server_access_test.exs:21-38`. |
| Each narrowing value builds the same options as today | Met | `read_only` gives `dont_ask` plus the three read tools (`providers.ex:137-138`). `plan` and `accept_edits` go through `providers.ex:140`. Codex `read_only`/`workspace_write` still set `sandbox` (`providers.ex:121`) and `ignore` still sets `ignore_user_config: true` (`:122`). Fresh and resumed turns are covered in `test/gen_agent_server_lifecycle_test.exs:353-385`. |
| The new Claude modes build the matching `--permission-mode` | Met for the options the server builds; the CLI flag is not verifiable by reading | `providers.ex:140` passes `:auto`, `:bypass_permissions`, `:dont_ask` through unchanged. The adapter accepts them (`deps/gen_agent_claude/lib/gen_agent/backends/claude.ex:164`) and the wrapper turns them into `bypassPermissions`, `dontAsk` and `auto` (`deps/claude_wrapper/lib/claude_wrapper/query.ex:1434-1437`). No test checks the actual `--permission-mode` argv for the new modes. The Codex equivalent does exist (`lifecycle_test.exs:380-384`). |
| Profiles, dynamic routes and startup agents share the default; their tests are updated | Met | `profiles.ex:59-62`, `instance_spec.ex:44-57`, and `runtime_config.ex:63`, which now calls `Providers.backend_opts`. Tests: `access_test.exs:99-116,162-187`, `lifecycle_test.exs:109,132-137`, `extensions/patterns/test/gen_agent_server_run_test.exs:15-21,41`. |
| `describe_instance` and the operation schemas list the new values | Met | `ops.ex:337-359`. Tested in `access_test.exs:118-158` and `extensions/mcp/test/gen_agent_server_mcp_lifecycle_test.exs:223`. |
| Format, warnings-as-errors compile, tests and extension matrix pass | Not verifiable by reading | The operator runs these. |

## 2. Defects

**1. The doc rewrites removed documentation the issue didn't touch.**
- `extensions/mcp/README.md:110-111`: the replaced paragraph also held the `effort` values per provider, the Codex `model_reasoning_effort` note, "`echo` accepts only `name` and `provider`", "`cwd` must be an absolute existing directory", the model-name rules, the `codex_response_text` behaviour, and the limits (16 routes, `max_in_flight` ≤ 64, `max_results` ≤ 1000). I searched the rest of the file and none of it appears elsewhere.
- `README.md:39-51`: removed "Both keep their native project instructions and separate provider sessions" and the `mix gen_agent_server ask PROVIDER PROMPT` versus IEx sentence.
- `README.md:162-174`: removed the "Codex CLI still handles its own authentication; this setting does not provide credentials" note and the "use a separate worktree for coding tasks and review changes before merging" advice.
- **Fix:** restore those sentences and change only the access wording.

**2. The same access paragraph is pasted into four places.**
- It appears at `README.md:39-51` and `README.md:162-174`, `extensions/mcp/README.md:113-125`, and `resources.ex` (Quickstart).
- In `README.md`, line 162 joins it onto the end of the profiles paragraph without wrapping, so the line runs about 130 characters. Lines 52 and `extensions/mcp/README.md:126` leave double blank lines.
- `extensions/mcp/README.md:128-129` then repeats the `read_only` → `dontAsk` + Read/Grep/Glob sentence directly below the pasted copy.
- **Fix:** keep one copy in `README.md`, link to it from the second spot, and drop the repeated `read_only` sentence in the MCP README.

**3. The control review check is weaker for Codex.**
- `extensions/control/lib/gen_agent_server/control/controller.ex:296-301` accepts a Codex review route when `codex_sandbox: :read_only` is set explicitly. It does not check `codex_user_config`.
- Before this change, such a route also ignored the user's config by default. Now it inherits `~~/.codex/config.toml`, including the user's MCP servers. A read-only sandbox does not limit what those MCP tools can do.
- `extensions/control/README.md:24-25` still describes the route as read-only.
- **Fix:** add `codex_user_config: :ignore` to the Codex `review_route?` clause, add a control test row for `read_only` + `inherit`, and say in the control README that a review route needs both settings. If you'd rather accept the risk, at minimum document that a read-only review route now inherits user MCP servers.

**4. The access value lists are hand-copied into five files.**
- The seven Claude values and three Codex values now appear separately in `providers.ex:91-99`, `instance_spec.ex:45-55`, `profiles.ex:64,76-84`, `pattern_spec.ex:152-175` and `ops.ex:339-357`.
- Nothing checks the copies against each other. The `effort` enum already avoids this by calling `Providers.efforts/1` (`ops.ex:329`).
- **Fix:** add `Providers.access_choices(:claude_permission_mode | :codex_sandbox | :codex_user_config)` and derive the other four lists from it, including the Ops enums via `Atom.to_string/1`.

**5. Startup agents now pick up `:provider_overrides`, which the issue didn't ask for.**
- `runtime_config.ex:63` now goes through `Providers.backend_opts`. That merges `:provider_overrides` and applies `ChildEnv.harden_backend_opts` while `config/runtime.exs` is being evaluated (`providers.ex:72-77`). Previously RuntimeConfig built raw options and hardening ran only at instance start (`instance.ex:26`).
- Hardening is idempotent (`child_env.ex:61-65`), so applying it twice is harmless.
- The overrides are the real issue: they apply only if `:provider_overrides` is already in the app env when runtime.exs runs. An override set later in the same runtime.exs is silently skipped.
- **Fix:** either document in the `RuntimeConfig` moduledoc that startup agents get overrides that are set before `from_env!` runs, or add a private builder in `Providers` that skips overrides and call that from RuntimeConfig.

**6. Some test names and docstrings are now inaccurate.**
- `extensions/patterns/test/gen_agent_server_run_test.exs:168` is still called "edit modes are opt-in". Under inherit, edit access is no longer opt-in.
- `extensions/patterns/lib/gen_agent_server/pattern_spec.ex:61` lists `codex_user_config` as `"ignore"` or `"inherit"` without saying `inherit` is the default. The neighbouring keys do say which value is the default.
- **Fix:** rename the test and add "(default)" to the docstring.

**7. `bypass_permissions` is now open to every client without a note.**
- MCP `create_instance` clients can request `bypass_permissions`, and so can profile and pattern specs (`instance_spec.ex:45-53`).
- The issue asks for this. But the old README sentence "The server rejects ... Claude's bypass mode from profile configuration" was deleted, and nothing replaced it.
- **Fix:** add one sentence to the MCP README and Capabilities resource saying that MCP clients can now request `bypass_permissions`.

## 3. Changes the issue did not ask for

- **RuntimeConfig refactor** (`runtime_config.ex:58-65`), which removes the duplicate `@backends` map and per-provider options. Keep it: it is the way startup agents share the default. Address the overrides side effect in defect 5.
- **Pattern spec `read_only` for Claude** (`pattern_spec.ex:169`). Pattern specs didn't accept it before. Keep it: it matches the other surfaces.
- **Profiles `read_only` for Claude** (`profiles.ex:78`). Also newly accepted; keep it for the same reason.
- **"Reproducing the previous complete Codex configuration requires both `read_only` and `ignore`"** in the docs. Keep it: it is useful migration guidance for a breaking change.
- **Control test rows for the new modes** (`extensions/control/test/gen_agent_server_control_controller_test.exs:338,344-347`). Keep them: they confirm the review check rejects the new values.
- **The doc deletions in defect 1.** Revert them.

REQUEST CHANGES

I’ll fix all seven defects, including the stricter Codex review check and startup construction without overrides, then rerun the full check matrix.

The access allowlists now come from `Providers.access_choices/1`. RuntimeConfig uses a small internal entry point to the existing private builder, so it shares defaults without reading overrides or capturing the child environment. The Codex review tests now distinguish explicit `ignore` from inherited or omitted user config.

All seven fixes are implemented. The root run has 119 passes and the same seven sandbox-related CLI failures. I also caught and removed a warning in the new control test. I’m finishing verification, including format and warnings-as-errors compilation in every extension.

Fixed all seven defects:

1. Restored unrelated README guidance: effort/model rules, route limits, response-text behavior, authentication, native sessions, CLI versus IEx, and worktree advice.
2. Kept one main access explanation in the root README, linked other sections to it, and removed repetition and extra blank lines.
3. Codex review admission now requires explicit `read_only` **and** `codex_user_config: ignore`. Added inherited/omitted-config rejection tests and README guidance.
4. Added `Providers.access_choices/1`; providers, profiles, dynamic routes, schemas, and patterns derive their allowlists from it.
5. RuntimeConfig uses the private provider builder through an internal entry point that skips overrides and defers environment hardening. Added a regression test.
6. Renamed the inaccurate pattern test and documented `inherit` as the user-config default.
7. Added explicit `bypass_permissions` availability notes to the MCP README and Capabilities resource, with a resource assertion.

Ran `MIX_OS_CONCURRENCY_LOCK=0 mix format`, `mix compile --warnings-as-errors`, and `mix test` in the root and every extension. Formatting and compilation passed throughout.

| Test project | Result |
|---|---:|
| Root | 119/126 passed |
| control | 95 passed |
| mcp | 32/33 passed |
| patterns | 17/18 passed |
| peers | 0/19 passed |
| public_source | 7 passed |
| schedule | 5 passed |
| selection | 8 passed |

Remaining failures match the sandbox restrictions: seven root CLI assertions and one patterns JSON assertion encounter Mix’s TCP `:eperm` warning; MCP’s socket test and all 19 peers tests fail with `{:error, :eperm}`.

All seven focused access tests and `git diff --check` pass. Your reported host results cover the prior revision; this revised change still needs host verification.

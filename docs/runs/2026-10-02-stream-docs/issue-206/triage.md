Re-checked at `8f6cb9d` (HEAD of `docs/ensemble-echo-example-206`). The issue still holds on current code. No files were edited.

## Claims that still hold

- **The moduledoc example uses an undefined module.** `extensions/ensemble/lib/gen_agent_ensemble.ex:15` has `{"worker-a", MyAgent, backend: GenAgent.Backends.Mock}`. This is the only `Mock` reference in the ensemble's `lib/`, `guides/`, `README.md`, `CHANGELOG.md` and `mix.exs`.
- **The runtime config comment is still there.** `extensions/ensemble/config/runtime.exs:17` says "switch the relevant ensembles to a different backend (e.g. GenAgent.Backends.Mock for local-only use)". `config/` is in the ensemble package's `files:` (`extensions/ensemble/mix.exs:87`), so the comment ships.
- **`Mock` is test-only.** `GenAgent.Backends.Mock` is defined only in `test/support/mock_backend.ex:1` and `extensions/ensemble/test/support/mock_backend.ex:1`.
  - Both `mix.exs` files compile `test/support` only under `:test` (`mix.exs:31-32` in each).
  - Neither package's `files:` includes `test` (`mix.exs:88`, `extensions/ensemble/mix.exs:87`).
- **The backend is called unconditionally at agent start.** `lib/gen_agent/server.ex:163` calls `backend.start_session(backend_opts)`, so a copied example fails with an undefined module.
- **Echo is shipped and usable.** `GenAgentEnsemble.Backends.Echo` is in `extensions/ensemble/lib/gen_agent_ensemble/backends/echo.ex`. Its options are `:transform` and `:delay_ms`, and it runs without credentials. `GenAgentEnsemble.Agents.Simple` is also shipped and pairs with it. `echo_test.exs:60-80` already tests Solo + Simple + Echo through `ask/2`.

## Details that differ from the issue text

- **Line number drift.** The `start_session` call is at `lib/gen_agent/server.ex:163`, not `:147-149`. The `mix.exs` lines are `:31-32` and `:87/:88`, not `:30-32` and `:78-88`. The substance is unchanged.
- **The root `README.md:517` is not a problem.** It describes `Mock` as "the test suite uses ... (in `test/support/`)", which is accurate, so leave it alone.
- **Already correct.** The ensemble README (lines 63, 186), `config/config.exs:26-35`, `guides/workflows/solo.md:89` and the Echo moduledoc already use `GenAgentEnsemble.Backends.Echo`. The `GenAgentEnsemble.Agents.Simple` moduledoc uses `GenAgent.Backends.Anthropic`, which is a shipped backend, so it is also fine.
- **The example's other lines are accurate.** `poll/2` returns `{:ok, :pending}` or `{:ok, :completed, response}` (`server.ex:306`). Only the `agent:` line needs to change.
- **No test covers the docs today.** Nothing in `extensions/ensemble/test` reads source docs or moduledocs, and there are no doctests.

## Plan: smallest change

1. **`extensions/ensemble/lib/gen_agent_ensemble.ex:15`**
   - Change `{"worker-a", MyAgent, backend: GenAgent.Backends.Mock}` to `{"worker-a", GenAgentEnsemble.Agents.Simple, backend: GenAgentEnsemble.Backends.Echo}`.
   - Reformat the list onto multiple lines to match the Echo moduledoc style.
   - This makes the example copy-pasteable. If keeping `MyAgent` is preferred, only the backend needs to change, but `Simple` avoids a second undefined module.
   - Optionally change `ask`'s result to match Echo (`{:ok, %{text: ...}}`). It currently binds `{:ok, response}`, which is already valid.

2. **`extensions/ensemble/config/runtime.exs:15-18`**
   - Change the comment text from `GenAgent.Backends.Mock` to `GenAgentEnsemble.Backends.Echo`, keeping "for local-only use".

3. **New test, e.g. `extensions/ensemble/test/gen_agent_ensemble/docs_references_test.exs`**
   - Read `lib/gen_agent_ensemble.ex` and `config/runtime.exs` with `File.read!`.
   - Assert neither contains `GenAgent.Backends.Mock`, and both reference `GenAgentEnsemble.Backends.Echo`.
   - Add a case that `Code.ensure_loaded?(GenAgentEnsemble.Backends.Echo)` and `Code.ensure_loaded?(GenAgentEnsemble.Agents.Simple)` are true.
   - Add a case that starts an ensemble with the moduledoc's `agent:` tuple and does the `tell`/`poll` and `ask` round trip against Echo. This is the "each case" acceptance coverage, since `echo_test.exs` only covers `ask/2`.
   - Optionally scan `README.md`, `guides/**/*.md`, `lib/**/*.ex` and `config/*.exs` for `Backends.Mock` so the check covers all package-shipped docs.

4. **Leave unchanged:** both `test/support/mock_backend.ex` files, the root `README.md`, `mix.exs` and `server.ex`.

Verification, run by the caller as instructed: `mix format --check-formatted`, `mix credo --strict` and `mix test` in `extensions/ensemble`.
I’ll inspect the implementation and locked adapters, focusing on validation, lifecycle behavior, and whether model and effort settings survive resumed turns. I’ll keep the review read-only and use no network commands.


The locked adapters retain model and effort options on resumed turns, including Codex’s fixed config override. I also found a compiler-warning issue in `Ops` and am checking how MCP schema validation interacts with the new tests and stable-error claims.


Read-only checks confirmed two blockers: `Ops` emits a warning that fails warnings-as-errors, and the duplicate-name test expects `instance_exists` for `server/default`, but validation returns `invalid_instance_name`. The new files also fail a formatting comparison. I’m finishing a small in-memory MCP lifecycle check; the full suite and release smoke remain for the host.


REQUEST CHANGES

- **P1 — Compiler warning blocks validation.** `lib/gen_agent_server/ops.ex:342`: `config_schema/0` separates the `schema_type/1` clauses. In-memory compilation confirms the grouping warning, which fails `mix compile --warnings-as-errors`. Move all clauses together.

- **P2 — New duplicate-name test fails with the default configuration.** `test/gen_agent_server_lifecycle_test.exs:234`: the test expects `instance_exists` for `server/default`, but `InstanceSpec` rejects `/` before checking existence. I reproduced `invalid_instance_name`. Align the assertion with the intended validation precedence.

- **P2 — Formatting gate fails.** `lib/gen_agent_server/instance_spec.ex:142`, `lib/gen_agent_server/ops.ex:203`, and `test/gen_agent_server_lifecycle_test.exs:85`: read-only formatter comparisons found differences. Format the changed files before the host runs CI’s `mix format --check-formatted`.

The in-memory MCP create → ask → stop check passed. Locked adapter code preserves model and effort across resumed turns. Full tests and packaged-release smoke were not run; no files were changed.
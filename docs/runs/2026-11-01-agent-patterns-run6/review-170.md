I've read the change and every spawn path it touches. I couldn't run anything, so test results are the operator's to confirm.

## 1. Acceptance items

| Item | Status | Evidence |
|---|---|---|
| Every spawn path scrubs `RELEASE_*`, `BINDIR`, `ROOTDIR` and the release `PATH` entries | **Met** | All one-shot spawns go through `Runner.run/3` → `Config.execution_opts/1` (`lib/codex_wrapper/runner.ex:234`, `lib/codex_wrapper/config.ex:263-270`). That covers `Command.run`, every `Commands.*`, `raw/2` (`lib/codex_wrapper.ex:82`) and `ExecFork.supported?` (`exec_fork.ex:292`). The observed and evidenced helpers call `execution_opts` directly (`observed_execution.ex:57`, `evidenced_execution.ex:46`). Streams call `Config.stream_opts/1` → `cmd_opts/1` (`exec.ex:373`, `exec_resume.ex:326`, `review.ex:300`, `exec_fork.ex:471`) inside the lazy `span_stream` function (`telemetry.ex:204-211`), so the parent environment is read when the stream is consumed. `Session` delegates to `Exec`/`ExecResume` (`session.ex:227,238,260,266`). The variable and `PATH` rules are in `child_env.ex:24-41` and `69-93`. |
| `Config.env` applies after the scrub; an explicit `PATH` is still scrubbed | **Met** | `child_env.ex:56-60` appends the overrides after `release_scrub/1` and runs a string `PATH` through `scrub_path/2` against the parent's markers. Last entry wins in Port's `Port.open` env list and in Forcola's `split_env` (`forcola.ex:352-365`). |
| No change without `RELEASE_ROOT`, or with `:inherit` | **Met** | `child_env.ex:55,61-63` returns only the validated overrides. `cmd_opts/2` adds `:env` only when it is non-empty (`config.ex:257`), so the options match the previous output. |
| Unit tests use a fabricated parent; one fake-CLI test per runner path | **Met by reading** | `child_env_test.exs` passes `@parent` maps throughout. `release_env_test.exs` runs builders (execute and stream), `Session` send/stream, every `Commands.*` call, `raw`, the fork probe, overrides, inherit, no-`RELEASE_ROOT` and late environment reads on both runners, plus Forcola observed/evidenced and `env_mode: :replace`. Whether they pass is for the operator to confirm. |
| README section and CHANGELOG entry | **Met** | `README.md` "Running from a release"; `CHANGELOG.md:7,12`. |

## 2. Defects

1. **`lib/codex_wrapper/runner.ex:81`: the runner contract documentation is now wrong for the default case.** The typedoc says `:env` is a "list of `{name, value}` string tuples". With this change, every spawn inside a release passes `{name, false}` entries for `BINDIR`, `ROOTDIR` and every `RELEASE_*`. Before, that only happened when a caller asked for an unset. A custom runner written against the documented contract, for example one that forwards `:env` to something that only takes strings, now breaks by default in a release. The CHANGELOG breaking entry (`CHANGELOG.md:7`) doesn't mention this.
   - **Fix:** change the typedoc to ``{name, String.t() | false}` tuples; `false` removes an inherited variable``, and add a sentence to the CHANGELOG breaking entry saying custom runners must honour `false` entries.

2. **Breaking-change marker.** `CHANGELOG.md:7` files this under Breaking Changes, but the branch commit `352ffb4 feat(env): scrub release boot variables from child processes` has no `!`. Release-please generates its section from the commit, so the generated 0.10.0 notes would list this as an ordinary feature.
   - **Fix:** title the squash commit / PR `feat(env)!: ...`, or add a `BREAKING CHANGE:` footer.

3. **Minor, non-blocking: the parent environment is read twice per Forcola one-shot.** `config.ex:265` reads `System.get_env()` to compute the scrub. When the scrub contains any unset, `forcola.ex:338` reads `System.get_env()` again to build the replacement environment. A `RELEASE_*` variable added in between would be in the second read but not in the unset list, so it would reach the child. Real releases don't do this at runtime, so no change is needed now. If wanted, the first read could be threaded through as an option.

## 3. Additions the issue did not ask for

- **Public `ChildEnv.normalize/3`** (`child_env.ex:51`): it mirrors gen_agent_server's `normalize/2` and gives callers a way to compose with their own overrides. **Keep.**
- **`execution_opts/1` dropping the parent `PATH` under `env_mode: :replace`** (`config.ex:266-268`): without it, a release host would inject its `PATH` into an environment the caller asked to replace. It is a correctness fix and has its own test. **Keep.**
- **Validating `release_env` in `cmd_opts/2` for hand-built structs** (`config.ex:253`): consistent with how `base_args/1` re-validates `verbose`. **Keep.**
- **`:release_env` in `@config_keys`** (`lib/codex_wrapper.ex:278`): needed so the convenience functions accept the option. **Keep.**
- **README cookie-file caveat:** comes straight from the issue's evidence. **Keep.**

REQUEST CHANGES

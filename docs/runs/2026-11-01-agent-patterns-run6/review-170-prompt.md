You are reviewing a change to codex_wrapper, an Elixir wrapper for the Codex CLI, in an open pull request; it is already committed. The current directory is the worktree with the change applied. You can read any file. You cannot run commands; the operator runs the checks.

Review the change against the issue below. Report:
1. For each acceptance item: met, not met, or not verifiable by reading, with the file and line that shows it.
2. Defects: incorrect behaviour, races, missing cases, inconsistencies with the surrounding code's conventions, doc claims the code does not support. For each, file:line, what is wrong, and a concrete fix.
3. Anything in the diff that the issue did not ask for, and whether it should stay.
4. A verdict on the last line: APPROVE or REQUEST CHANGES.

Report only what you can point to in the code. Before calling code dead or unused, search the whole repository, including extensions and tests. Do not restate the change.


# Issue #156
## feat(env): scrub release boot variables and PATH entries from the codex child

When an application runs from a mix release, the release start script exports `RELEASE_*` (including `RELEASE_COOKIE`), `erl` exports `BINDIR` and `ROOTDIR`, and the release's `erts-<vsn>/bin` and `bin` directories come first on `PATH`. The wrapper passes the VM's environment to `codex` unchanged (`Config.cmd_opts/1` adds only `Config.env`, `lib/codex_wrapper/config.ex:186-194`), so the commands codex runs inherit it, and a project's own `elixir` or `mix` resolves `erl` from the release and cannot boot.

| Before | After |
|---|---|
| From a release, `mix --version` or `elixir -e 'IO.puts(:ok)'` run by codex in a project directory exits 1 with `Runtime terminating during boot ({'cannot get bootfile','<release>/bin/start.boot'})`. | It boots from the project's own Erlang and Elixir. |
| `RELEASE_COOKIE`, `RELEASE_NODE` and the other `RELEASE_*` values reach every command codex runs. The release script assigns most of them as `${RELEASE_X:-default}`, so a project release that codex starts adopts the host's `RELEASE_NAME`, `RELEASE_NODE`, `RELEASE_COOKIE`, `RELEASE_VM_ARGS` and `RELEASE_TMP`. | These variables are unset in the child. |
| Each application copies a scrub like gen_agent_server's `ChildEnv` and has to know which unset form each runner path accepts. | `Config` scrubs by default when the VM runs from a release, on every spawn path. |

## Evidence

codex_wrapper 0.8.1 (`lib/` as of 7f472e6), Elixir 1.20.4 on OTP 29 (erts 17.1.1), macOS 27.0.1 arm64. A minimal `mix release` ran `CodexWrapper.Exec.execute/2` under `bin/relprobe eval` against a fake CLI that logs its environment and then runs `elixir -e` in an unrelated directory:

```text
BINDIR=<rel>/erts-17.1.1/bin
ROOTDIR=<rel>
RELEASE_COOKIE=<set> RELEASE_NODE=relprobe RELEASE_ROOT=<rel> RELEASE_VM_ARGS=<rel>/releases/0.1.0/vm.args ... (15 RELEASE_* variables)
PATH=<rel>/erts-17.1.1/bin:<rel>/bin:...
which erl=<rel>/erts-17.1.1/bin/erl
elixir exit=1
Runtime terminating during boot ({'cannot get bootfile','<rel>/bin/start.boot'})
```

A second fake that runs `mix --version` gets the same `cannot get bootfile` error and exit status 1. Outside a release both fakes succeed (`child elixir ok`, and `mix --version` exits 0). From inside the release, unsetting `BINDIR` and `ROOTDIR` alone, or every `RELEASE_*` alone, still fails; removing the two release `PATH` entries alone lets `elixir` boot. The cookie is also stored in `$RELEASE_ROOT/releases/COOKIE`, readable by the same OS user, so unsetting `RELEASE_COOKIE` narrows where it is exposed and is not an isolation boundary on its own.

codex's `shell_environment_policy` setting (`codex exec --help` shows `-c shell_environment_policy.inherit=all`) applies to the commands codex runs, not to the environment the codex process itself starts with.

Prior art: genagent/gen_agent_server [`lib/gen_agent_server/child_env.ex`](https://github.com/genagent/gen_agent_server/blob/0bbb1dac21b459d4d5282645e46eeccc5791a631/lib/gen_agent_server/child_env.ex) and [README.md lines 146-174](https://github.com/genagent/gen_agent_server/blob/0bbb1dac21b459d4d5282645e46eeccc5791a631/README.md#provider-child-environment). It unsets `RELEASE_*`, `BINDIR` and `ROOTDIR`, removes whole `PATH` entries equal to `BINDIR`, `ROOTDIR/bin`, `RELEASE_ROOT/bin` or `<ROOTDIR|RELEASE_ROOT>/erts-<vsn>/bin`, and applies after trusted overrides. Its README records that it passes `false` for unsets on the streaming paths.

`Runner.Forcola` one-shot calls accept only string `:env` values (the default interrupt options added in 0.8.1 make every `Forcola.run/2` call validate them), and `Forcola.Stream` rejects `env_mode`, so on the Forcola paths the scrub depends on the unset fix listed below.

## API sketch

```elixir
# default: scrub when RELEASE_ROOT is set; no effect outside a release
config = CodexWrapper.Config.new(release_env: :scrub)

# opt out
config = CodexWrapper.Config.new(release_env: :inherit)

# the entries the runners apply, for callers that build an environment themselves
CodexWrapper.ChildEnv.release_scrub(System.get_env())
#=> [{"BINDIR", false}, {"PATH", "/usr/local/bin:/usr/bin:/bin"}, {"RELEASE_COOKIE", false}, ...]
```

## Acceptance

- [ ] With `RELEASE_ROOT` set, every spawn path (`Exec`, `ExecResume`, `Review`, `ExecFork`, `Session` and the `Commands.*` modules, execute and stream, on `Runner.Port` and `Runner.Forcola`, and `raw/2`) unsets `RELEASE_*`, `BINDIR` and `ROOTDIR` and removes whole `PATH` entries equal to `BINDIR`, `ROOTDIR/bin`, `RELEASE_ROOT/bin` or `<ROOTDIR|RELEASE_ROOT>/erts-<vsn>/bin`.
- [ ] `Config.env` entries apply after the scrub, so a caller can set a scrubbed name explicitly (gen_agent_server instead forces the scrub over its overrides); a `PATH` given in `Config.env` still has the release entries removed.
- [ ] Nothing changes when `RELEASE_ROOT` is unset, or with `release_env: :inherit`.
- [ ] Unit tests use a fabricated parent environment (as gen_agent_server's `normalize/2` does); one fake-CLI test per runner path checks the child's environment.
- [ ] README section and a CHANGELOG entry for the new default.

## Related

- genagent/claude_wrapper_ex#310 ("feat(env): scrub release boot variables and PATH entries from the claude child")
- genagent/claude_wrapper_ex#309 ("fix(env): Config.env unset entries behave differently on each runner path") (prerequisite)
- #127 (isolated evidenced execution, `env_mode`)

# Diff of PR #170

The diff of PR #170 at that point was included here.

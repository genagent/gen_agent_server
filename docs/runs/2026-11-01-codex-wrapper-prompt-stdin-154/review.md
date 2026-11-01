Verdict: **REQUEST CHANGES**. The main reason is defect 1: on hosts without `/usr/bin/getconf`, every command can be rejected before it runs. I read the code only; I could not run anything, so whether the tests pass is not verified.

## 1. Acceptance items

**1. All four commands send the prompt on stdin with `-` as the positional: met.**
- **Argv side:** `Command.prompt_arg/1` (`lib/codex_wrapper/command.ex:39-42`) is used at `exec.ex:411`, `exec_resume.ex:359`, `review.ex:334` and `exec_fork.ex:541`.
- **Prompt bytes, by path:**
  - execute: `command.ex:29`
  - stream: `exec.ex:373`, `exec_resume.ex:326`, `review.ex:300`, `exec_fork.ex:471`
  - observed: `observed_execution.ex:57`
  - evidenced: `evidenced_execution.ex:46`
- **Runners:** Port at `runner/port.ex:73` and `:102`. Forcola at `runner/forcola.ex:183` and `:400`.
- **Session:** `Session.send/3` and `Session.stream/3` go through `Exec` and `ExecResume` (`session.ex:227,238,260,266`).
- **Tests:** covered in `test/codex_wrapper/prompt_stdin_test.exs`.

**2. Prompt file is 0600 in a 0700 directory, unlinked before codex runs, and removed on failure: met.**
- **Permissions:** the file is created under `umask 077` (`stdin_file.ex:7-10`).
- **Unlinked before codex runs:**
  - Port: removed at `command.ex:137-139`, before the target starts at `command.ex:150`.
  - Forcola: removed by the launcher (`forcola.ex:248-256`) before it runs `exec "$@"`.
- **Wrapper cleanup:**
  - execute: an `after` block (`stdin_file.ex:16-21`).
  - stream: the resource close callback (`stdin_file.ex:25-43`).
- **Caveat:** if the calling process is killed by an exit signal, the `after` block does not run. The PR body discloses this.

**3. Fake CLI tests: met as written.**
- The 2 MiB prompt test checks byte count and SHA-256 (`prompt_stdin_test.exs:19-31`).
- The `ps -ww` privacy test and the timeout signal-schedule test are in `prompt_stdin_lifecycle_test.exs:18-81`.
- Forcola streaming gets only TERM and KILL. That is the schedule it already had (`forcola.ex:25-28`, pre-existing text), so "still reaches" holds. The PR body marks this item unmet; the issue author should decide which reading applies.

**4. Oversized argument lists return a typed error before spawning: met.**
- The check is in `argv.ex:12-34`, called at `port.ex:72`, `:82` and `:99`, and at `forcola.ex:180` and `:398`.
- Tests are in `argv_test.exs`.

**5. `prompt_input: :argv` keeps the old form, and a prompt of `-` has defined behaviour: met.**
- Argv mode: `command.ex:42`.
- A prompt of exactly `-` is sent as literal text on stdin in both modes: `command.ex:50-51`.
- The `ExecFork.prompt/2` doc says so: `exec_fork.ex:155-162`.

## 2. Defects

1. **Missing `getconf` blocks every command (`argv.ex:84-97`, `argv.ex:46`).**
   - `/usr/bin/getconf` is a hard-coded path. When it is missing (NixOS, Guix, some minimal images), the limit falls back to `ARG_MAX = 32_768`, and that budget includes the inherited environment.
   - `Port.run/4` validates every command (`port.ex:72`), including `version`, `auth` and `mcp`, not just prompt commands.
   - A nix-shell or CI environment over about 28 KiB would make every call fail with `{:argument_list_too_long, ...}`. Before this change those calls worked.
   - **Fix:**
     - Find `getconf` with `System.find_executable("getconf")`, keeping `/usr/bin/getconf` as a fallback.
     - If it still can't be read, use the platform default (`2_097_152` on Linux, i.e. an 8 MiB stack / 4, and `1_048_576` on Darwin) instead of 32 KiB.

2. **Limits are re-read with new subprocesses on every call (`argv.ex:14,40-48`).**
   - `limits/0` runs `getconf` once on macOS and twice on Linux. `Argv.validate/3` runs twice per invocation (`port.ex:72` then `:82`; `forcola.ex:180` then `:239`).
   - So each Port run spawns 2 to 4 `getconf` processes plus the `/bin/sh` that creates the prompt file (`stdin_file.ex:50`).
   - **Fix:** cache the limits in `:persistent_term` on first use (RLIMIT_STACK is fixed for the VM's lifetime in practice), or compute them once per invocation and pass them to `validate/4`.

3. **The prompt directory name is only unique within one VM (`stdin_file.ex:48-49`).**
   - The name comes from `make_ref()` alone. A ref is unique within a node, not across VMs: two non-distributed VMs (`nonode@nohost`) sharing `System.tmp_dir!()` can produce the same name.
   - A collision makes `mkdir` fail, which returns `{:error, {:stdin_file, {:create, 1}}}` with no retry. It fails safe because `mkdir` is exclusive, but it is a spurious failure, for example with parallel `mix test` runs in sibling worktrees.
   - **Fix:** add `:crypto.strong_rand_bytes(16)` (or `System.os_time` plus `:os.getpid()`) to the name, and retry a few times on a `mkdir` failure.

4. **The `|| exit 125` handlers in both launchers don't run under POSIX `sh` (`command.ex:137`, `forcola.ex:250`).**
   - A redirection error on the special builtin `exec` makes a non-interactive POSIX shell exit immediately, before `|| exit 125`. Typically the status is 2 under dash and 1 under bash in POSIX mode.
   - On Port, the caller then gets `{:ok, {"sh: ...", 2}}` with the shell's message merged into stdout, not a distinguishable status.
   - **Fix:** use `command exec 4<"$stdin_file" || exit 125`, since `command` suppresses the special-builtin exit. Or drop the `exit 125` lines and stop implying a sentinel.

5. **Missing executable on Forcola evidenced runs reports `:pre_spawn` (`forcola.ex:173-176` with `:194`).**
   - With a prompt, a missing executable now returns `{:error, {:spawn, :executable_not_found}}` with `termination: :pre_spawn`.
   - Without a prompt, the same failure reports `termination: {:spawn, reason}` (`forcola.ex:367`).
   - **Fix:** return the not-found case from `with_launch` as `{project_error, %{termination: {:spawn, :executable_not_found}}}` so both forms match.

6. **`prompt_executable/2` can raise (`forcola.ex:192`).**
   - It calls `File.cwd!()`, which raises `File.Error` if the VM's cwd has been deleted. That escapes `run/4` instead of returning a runner error.
   - **Fix:** use `File.cwd()` and return `{:error, {:spawn, reason}}`.

7. **The commits are not marked as breaking.**
   - The default argv changes from the prompt to `-`.
   - Custom runners that ignore `opts[:stdin]` now make codex exit with "No prompt provided via stdin." (documented at `runner.ex:82-85` and in the README).
   - That is a breaking change, and the repo already marks those with `!` (`e99c936 fix(session)!:`). The commits are plain `feat:` (`63ea405`, `f200c7c`), so release-please will generate no BREAKING CHANGES entry.
   - **Fix:** title the squash commit or PR `feat!: deliver prompts on stdin`, with a `BREAKING CHANGE:` footer naming the argv change and the custom-runner `:stdin` requirement.

## 3. Changes the issue did not ask for

- **Port spawn failures become typed errors** (`port.ex:134-138` for streams, `port.ex:308-311` for execute). Previously they raised. Keep it, and add a changelog line, since stream consumers that rescued the raise will now see an error item instead.
- **NUL-in-argument check (`{:invalid_argument, index}`, `argv.ex:63-68`).** Keep: `Port.open` would raise on it anyway, and the error does not include the argument's contents.
- **Environment-size check.** Keep: `ARG_MAX` counts the environment, so checking argv alone would not meet acceptance item 4.
- **PATH resolution in the Forcola runner** (`forcola.ex:186-232`). It exists because the launcher hides spawn failures, so it is needed. Note that `System.find_executable/1` accepts any execute bit, which does not exactly match `execvp`. Keep it.
- **Evidenced path now calls `validate_options`** (`forcola.ex:160`). This duplicates the `validate_evidence` gate. It is harmless; keep it.
- **Longer owner-death wait in a test** (`observed_execution_test.exs:418-423`). This fixes an existing flaky test, not this feature. Keep it, but it would read better as its own `test:` commit.

REQUEST CHANGES

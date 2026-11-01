You are reviewing a change to codex_wrapper, an Elixir wrapper for the Codex CLI in an open pull request; it is already committed. The current directory is the worktree with the change applied. You can read any file. You cannot run commands; the operator runs the checks.

Review the change against the issue below. Report:
1. For each acceptance item: met, not met, or not verifiable by reading, with the file and line that shows it.
2. Defects: incorrect behaviour, races, missing cases, inconsistencies with the surrounding code's conventions, doc claims the code does not support. For each, file:line, what is wrong, and a concrete fix.
3. Anything in the diff that the issue did not ask for, and whether it should stay.
4. A verdict on the last line: APPROVE or REQUEST CHANGES.

Report only what you can point to in the code. Before calling code dead or unused, search the whole repository, including extensions and tests. Do not restate the change.

# Issue: feat: deliver the prompt on stdin instead of argv

`Exec`, `ExecResume`, `Review` and `ExecFork` pass the prompt as the last positional after `--` (`lib/codex_wrapper/exec.ex:391`, `407-412`; `exec_resume.ex:315`, `331-335`; `review.ex:314`, `330-334`; `exec_fork.ex:521`, `531`), and every runner gives codex an empty stdin (`</dev/null` in the Port launcher, `command.ex:96-99`; Forcola closes it after spawn). codex-cli 0.165.0 reads the prompt from stdin when the prompt positional is `-`, in `exec`, `exec resume`, `exec review` and `exec fork`.

| Before | After |
|---|---|
| A prompt of 131,072 bytes or more fails on Linux (per-string limit `MAX_ARG_STRLEN`), and about 1 MiB fails on macOS (`getconf ARG_MAX` is 1048576). `Runner.Port` reports it as `{:ok, %Result{exit_code: 7, success: false, stdout: ""}}` (errno `E2BIG` read as an exit status) and `Exec.stream/2` returns `[]`. | Prompt size is limited by codex, not by `execve`; an argument list over the platform limit is rejected before spawning with a typed error. |
| The prompt is in the process table for the whole run: three processes with `Runner.Port` (the supervisor shell, its watchdog subshell and codex), one with `Runner.Forcola`. On Linux `/proc/<pid>/cmdline` is mode 0444, readable by other local users. | argv carries `-` in place of the prompt. |
| `ExecFork.prompt/2` documents that a prompt of exactly `-` reads the prompt from stdin (`exec_fork.ex:140-146`), but stdin is always empty: `Exec.new("-")` returns `{:ok, %Result{stdout: "No prompt provided via stdin.\n", exit_code: 1}}`. | The wrapper passes `-` itself and writes the prompt to stdin. |

## Evidence

codex_wrapper 0.8.1 (`lib/` as of 7f472e6), codex-cli 0.165.0, Elixir 1.20.4 on OTP 29, macOS 27.0.1 arm64, and Linux 6.12 in the `elixir:1.20-otp-29` container.

`codex exec --help`:

```text
[PROMPT]
        Initial instructions for the agent. If not provided as an argument (or if `-` is used),
        instructions are read from stdin. If stdin is piped and a prompt is also provided, stdin
        is appended as a `<stdin>` block
```

The `exec resume`, `exec review` and `exec fork` help says "If `-` is used, read from stdin" for their prompt argument.

With `CODEX_HOME` set to an empty directory and no credentials, so every model request is rejected:

```text
$ codex exec --skip-git-repo-check --ephemeral -- - </dev/null
No prompt provided via stdin.                                   (exit 1)
$ printf 'stdin prompt marker 51b2' | codex exec --skip-git-repo-check --ephemeral --json -
{"type":"thread.started","thread_id":"..."}
{"type":"turn.started"}
... 401 Unauthorized: Missing bearer or basic authentication in header
```

Through the wrapper, with a fake CLI that reports the size of its last argument:

```text
macOS, 900,000-byte prompt     Runner.Port execute     {:ok, %Result{exit_code: 0}}
macOS, 1,100,000-byte prompt   Runner.Port execute     {:ok, %Result{stdout: "", exit_code: 7, success: false}}
                               Runner.Port stream      []
                               Runner.Forcola execute  {:error, {:spawn, {"spawn failed: Argument list too long (os error 7)", %Forcola.Result{}}}}
Linux, 131,000-byte prompt     Runner.Port execute     {:ok, %Result{exit_code: 0}}
Linux, 131,072-byte prompt     Runner.Port execute     {:ok, %Result{stdout: "", exit_code: 7}}
```

Process table during a `Runner.Port` run (`ps -ax -ww -o pid=,comm=,args=`), each line containing the prompt `PROMPT-MARKER-c0ffee do the thing`:

```text
/bin/sh -c watcher_ready=0 ... codex-wrapper <fake> exec -- PROMPT-MARKER-c0ffee do the thing   (supervisor)
/bin/sh <fake> exec -- PROMPT-MARKER-c0ffee do the thing                                        (the CLI)
/bin/sh -c watcher_ready=0 ... codex-wrapper <fake> exec -- PROMPT-MARKER-c0ffee do the thing   (watchdog subshell)
```

## Delivery on stdin

An Erlang port cannot close only the child's stdin (OTP 29 `open_port/2` has no such option), and `System.cmd/3` takes no input. In `Runner.Port`, the supervisor's target redirect `</dev/null` (`command.ex:96-99`) can become a redirect from a 0600 prompt file in a 0700 directory, with `-` as the positional and fd 3 still held for the watchdog. For `Runner.Forcola`, a `/bin/sh` launcher that opens the file, unlinks it and execs codex keeps the process group and the SIGINT-first schedule (#119); a 2 MiB prompt reached a fake CLI's stdin through `Forcola.run/2` this way, and the file was gone afterwards:

```elixir
script = ~S(f=$1; shift; exec <"$f" || exit 125; rm -f -- "$f"; exec "$@")
Forcola.run(["/bin/sh", "-c", script, "codex-wrapper", prompt_file, binary | args], opts)
```

`Forcola.Duplex` (`send_line/2`, then `send_eof/1`) would drop that schedule: forcola 0.7.0 rejects the interrupt options and `:env_mode` on Duplex.

## API sketch

```elixir
# default: the prompt goes to stdin and the positional is "-"
CodexWrapper.exec(prompt, sandbox: :read_only)

# previous behavior
CodexWrapper.Exec.new(prompt) |> CodexWrapper.Exec.prompt_input(:argv)
```

## Acceptance

- [ ] `Exec`, `ExecResume`, `Review` and `ExecFork` (execute and stream, `Runner.Port` and `Runner.Forcola`, `Session.send/3` and `Session.stream/3`) write the prompt to stdin and pass `-` as the prompt positional.
- [ ] The prompt file is created 0600 in a 0700 directory, unlinked before codex runs, and removed by the wrapper on spawn failure, timeout and halt.
- [ ] Fake CLI tests: a 2 MiB prompt arrives intact on stdin; `ps -ww` does not show the prompt; the INT, TERM, KILL schedule still reaches codex on timeout.
- [ ] An argument list over the platform limit returns a typed error before spawning instead of `exit_code: 7`.
- [ ] `prompt_input: :argv` keeps the current form. A caller prompt of `-` is either sent as literal text or rejected with a typed error, and the `ExecFork.prompt/2` doc says which.

## Related

- genagent/claude_wrapper_ex#306 ("feat: deliver the prompt on stdin instead of argv")
- #37 (the stdin hang that led to `</dev/null`), #88 (the `--` terminator), #119 (SIGINT-first termination)

# PR body

Closes #154.

## Changes

Prompts now travel on stdin by default, so a 2 MiB prompt does not consume the OS argument budget or appear in process arguments. `Exec`, `ExecResume`, `Review` and `ExecFork` emit `-` as the prompt positional. This applies to execute, stream, convenience APIs, initial and resumed session turns, and observed/evidenced execution.

- Add `prompt_input/2` builders and `prompt_input: :argv` compatibility options. A literal `-` is sent as text on stdin in either mode; omitted optional prompts remain omitted.
- Create prompt files with mode 0600 inside 0700 directories. Launchers open stdin and unlink the file and directory before starting codex. Wrapper cleanup covers startup failure, timeout, stream halt and stream exceptions; allocation is lazy for streams.
- Reject oversized arguments and environments before spawning, including launcher overhead and Linux per-string limits. Typed errors report sizes without argument contents; streams return `StreamError` events.
- Preserve Port watchdog and Forcola process-group cleanup. Retain Forcola typed failures for missing/non-executable targets and preserve a target's legitimate exit 127.
- Document custom runner stdin requirements and transport limitations. Add regression coverage for stream cleanup, PATH/cwd/symlink resolution, literal prompts, process-table privacy and signal delivery. Give the existing owner-death assertion time for its default two-second INT grace plus TERM delivery and reaping.

## Validation

Before the implementation push, all of these commands passed on macOS with Elixir 1.20.4 / OTP 29.1.2 and in Linux containers with Elixir 1.19.7 / OTP 27.3.4.19 and Elixir 1.20.5 / OTP 29.1.2:

`mix deps.get`, `mix deps.unlock --check-unused`, `mix hex.audit`, `mix compile --warnings-as-errors`, `mix format --check-formatted`, `mix credo --strict`, `mix dialyzer`, `mix test`, and `mix docs --warnings-as-errors`.

Each test run reported 692 tests, zero failures and four excluded opt-in authenticated integration tests. Forcola tests ran with its native shim.

`mix codex.contract` passed against native CLI versions 0.149.0, 0.164.0 and current latest 0.166.0 on macOS and Linux. The macOS contract runs used a temporary Codex config directory because the user's current config contains fields rejected by the oldest pinned CLI. No authenticated model requests were made. Release publication was not run.

GitHub pull request CI passed all five jobs: both Elixir/OTP combinations, Docs, and the two pinned CLI contracts.

## Acceptance

- [x] All four commands, both runners, execute/stream, and initial/resumed `Session.send/3` and `Session.stream/3` send prompt bytes on stdin with `-` in argv.
- [x] Prompt files have 0600/0700 permissions, are unlinked before codex runs, and are cleaned up on startup failure, timeout and stream halt.
- [ ] Full fake-CLI acceptance: 2 MiB byte counts and SHA-256 digests, `ps -ww` privacy, timeout escalation and forced child termination are tested. INT/TERM/KILL reaches Port execute/stream and Forcola one-shot children. Forcola streaming retains TERM/KILL only: locked Forcola 0.7.0 does not support interrupt options on its streaming API. The full three-signal requirement is therefore not met for that path.
- [x] Oversized argv/environment inputs return typed errors before the target starts, including observed/evidenced and streaming paths.
- [x] `prompt_input: :argv` retains positional prompts. A literal `-` is delivered as text in both modes, and `ExecFork.prompt/2` documents this behavior.

## Remaining limitations

An uncatchable owner or VM termination before the launcher unlinks the prompt can leave a private file. Once codex starts, the file is already unlinked. Executable preflight also cannot eliminate filesystem races; changes to the executable or its interpreter after validation can surface as a launcher exit status.


# Diff

The PR diff followed here; see final.diff.

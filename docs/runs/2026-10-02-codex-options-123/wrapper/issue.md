fix(codex): reject --ephemeral on resume turns and drop the undefined --verbose flag

Found in a read-only review of `main` at `b8f8ab4`. Code links point at that commit; `main` has moved since (core 0.4.0).

## Problem

### 1. Codex backend accepts :ephemeral and forwards --ephemeral on resume turns, although an ephemeral thread is not persisted and cannot be resumed

start_session/1 accepts :ephemeral (codex.ex:70, 259-271) and the backend passes --ephemeral on the fresh turn (175-176) and on every resume turn (221-222). Upstream Codex skips thread persistence and the state DB for ephemeral sessions (codex-rs/core/src/session/session.rs:1021-1023, 1134-1136), and `exec resume <uuid>` issues thread/resume and propagates its error (codex-rs/exec/src/lib.rs:1027-1046) without falling back to a new thread. From the second turn on, the agent would receive an error ({:error, :no_terminal_event} if the CLI exits without JSONL). The moduledoc (codex.ex:31-44) and README ([`integrations/codex/README.md:103-110`](https://github.com/genagent/gen_agent/blob/b8f8ab4/integrations/codex/README.md#L103-L110)) list :ephemeral among settings "forwarded on fresh and resumed turns" with no caveat. The real CLI was not run; the turn-2 failure is derived from upstream source. The "silently starts a new thread" variant in the merged report is not supported by current upstream code for UUID thread ids. Suggested fix: reject :ephemeral in start_session/1 the same way :cd, :add_dirs and :search are rejected, or document it as single-turn only. Comparing the thread id reported by thread.started with the requested resume id is a separate, optional hardening.

**Evidence.** codex.ex:175-176 and 221-222 forward ephemeral on Exec and ExecResume; codex.ex:33-37 and [`README.md:103-110`](https://github.com/genagent/gen_agent/blob/b8f8ab4/README.md#L103-L110) state these settings are forwarded on fresh and resumed turns. Upstream codex-rs/exec/src/cli.rs:40-42: "Run without persisting session files to disk." Upstream lib.rs:1911-1916 returns the UUID unchanged and issues thread/resume, which fails when the thread does not exist, so later turns would end without JSONL output; older CLI versions started a new thread instead. Reproduced only the argv: second-turn args were `exec resume --ephemeral --json -- t-1 second turn`. The real CLI outcome was not run. The backend also never compares the id in thread.started with the id it asked to resume, so a silently replaced thread would go unnoticed.

**Scenario.** Agent started with ephemeral: true. Turn 1 succeeds. Turn 2 runs `codex exec resume <id> --ephemeral`. Observed (depending on CLI version): {:error, :no_terminal_event} on every later turn, or a new thread with no memory. Expected: either continuation works or the option is rejected at start_session.

Reproduction from the review (private checkout, stub backend or fake CLI, no provider called):

```text
Stub runner set via Application.put_env(:codex_wrapper, :runner, CaptureRunner); stream_lines/4 sends {:command, binary, args} to the test process, returns thread.started(t-1) + agent_message + turn.completed for `exec`, and [] for `exec resume`.

  {:ok, session} = Codex.start_session(binary: "fixture-codex", ephemeral: true)   # accepted
  {:ok, first, _} = Codex.prompt(session, "first turn")
  events = Enum.to_list(first)
  # argv: ["exec", "--ephemeral", "--json", "--", "first turn"]
  session = Codex.update_session(session, Enum.find(events, &(&1.kind == :result)).data)
  # session.thread_id == "t-1"
  {:ok, second, _} = Codex.prompt(session, "second turn")
  Enum.to_list(second)  # [] with the stub
  # argv: ["exec", "resume", "--ephemeral", "--json", "--", "t-1", "second turn"]

Run: cd integrations/codex && mix test test/ephemeral_verify_test.exs  -> 1 passed, output as above.
```

### 2. verbose: true prepends a --verbose global flag that the Codex CLI source does not define

Added precision: (1) the flag is absent from the top-level, exec, and TUI clap definitions at tag rust-v0.157.1 (the installed version) and at rust-v0.100.0, rust-v0.117.0, and rust-v0.130.0, so no sampled CLI version accepts it; (2) the same prepend happens on resume turns (codex_wrapper exec_resume.ex:255), not only fresh turns; (3) the streaming path does not merge stderr (config.ex:95-99) and Runner.Port discards the exit status (runner/port.ex:69), so the caller gets only {:error, :no_terminal_event} with no diagnostic; (4) the root defect is in codex_wrapper (Config.base_args/1, still present on codex_wrapper_ex origin/main with a unit test asserting it), and gen_agent_codex propagates it by accepting and documenting :verbose. Rejection by the real CLI is inferred from upstream source and was not executed.

**Evidence.** codex.ex:28-29 and :62, [`README.md:99-100`](https://github.com/genagent/gen_agent/blob/b8f8ab4/README.md#L99-L100) list :verbose. deps/codex_wrapper lib/codex_wrapper/config.ex:71-73 returns ["--verbose"]; exec.ex:326 prepends base args. Reproduced argv with a fixture: `--verbose exec --json -- hello there`. grep for "verbose" in upstream codex-rs/cli/src/main.rs, codex-rs/utils/cli/src/shared_options.rs, codex-rs/exec/src/cli.rs and codex-rs/tui/src/cli.rs (openai/codex main ecc78e4) returned no flag definition. The wrapper's `mix codex.contract` task checks subcommand flags only, not Config.base_args. Not confirmed by running the installed CLI (0.157.1). The test fixture would also misclassify the turn because it checks $2 for "resume" (test/fixtures/codex_cli.sh:7).

**Scenario.** start_agent(..., backend: GenAgent.Backends.Codex, verbose: true), then GenAgent.ask. Observed (expected from the CLI source): clap error on stderr, exit code 2, {:error, :no_terminal_event}. Expected: a working turn with more diagnostics, or the option rejected at start.

Reproduction from the review (private checkout, stub backend or fake CLI, no provider called):

```text
fake/codex (chmod +x):
#!/bin/sh
dir=$(cd "$(dirname "$0")" && pwd)
printf '%s\n' "$@" >> "$dir/args.log"; printf -- '---\n' >> "$dir/args.log"
if [ "${1:-}" = "--verbose" ]; then printf "error: unexpected argument '--verbose' found\n" >&2; exit 2; fi
printf '%s\n' '{"type":"thread.started","thread_id":"t1"}'
printf '%s\n' '{"type":"item.completed","item":{"type":"agent_message","text":"ok"}}'
printf '%s\n' '{"type":"turn.completed","usage":{"input_tokens":1,"output_tokens":1}}'

probe.exs:
defmodule Probe.Agent do
  use GenAgent
  @impl true
  def init_agent(opts), do: {:ok, Keyword.take(opts, [:binary, :verbose, :skip_git_repo_check]), %{}}
  @impl true
  def handle_response(_ref, _resp, state), do: {:noreply, state}
end
bin = System.fetch_env!("FAKE_CODEX")
for verbose <- [false, true] do
  name = "probe-#{verbose}"
  {:ok, _} = GenAgent.start_agent(Probe.Agent, name: name, backend: GenAgent.Backends.Codex, binary: bin, verbose: verbose)
  IO.inspect(GenAgent.ask(name, "hello there"), label: "verbose=#{verbose}")
  GenAgent.stop(name)
end

Run: FAKE_CODEX=<abs path>/fake/codex MIX_ENV=test mix run <abs path>/probe.exs

Output:
verbose=false: {:ok, %GenAgent.Response{text: "ok", session_id: "t1", ...}}
error: unexpected argument '--verbose' found
verbose=true: {:error, :no_terminal_event}
args.log: `exec --json -- hello there` then `--verbose exec --json -- hello there`

Upstream check: gh api -H "Accept: application/vnd.github.raw" "repos/openai/codex/contents/codex-rs/cli/src/main.rs?ref=rust-v0.157.1" | grep -ci verbose  => 0 (same for exec/src/cli.rs, tui/src/cli.rs, utils/cli/src/shared_options.rs, utils/cli/src/config_override.rs).
```

## Proposed fix

- (1) Either reject :ephemeral in start_session/1 with a clear error, or document it as single-turn only and skip resume when it is set. Emit a warning or error when thread.started on a resume turn reports a different thread id than requested.
- (2) Confirm against the installed CLI, then remove :verbose from the accepted config keys and docs (and from codex_wrapper's Config.base_args/1), or map it to a supported mechanism.

## Acceptance

- A regression test reproduces each scenario above and passes after the change.

## Verification

- Confirmed by an independent code trace and reproduced by running code.
- Reported independently by 1 other review pass.


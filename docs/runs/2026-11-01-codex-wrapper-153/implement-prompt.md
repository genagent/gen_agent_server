You are implementing one GitHub issue in the codex_wrapper Elixir library. The current directory is a git worktree of the repository on branch feat/last-message-153. Dependencies are fetched and compiled; the network may be unavailable.

Constraints:
- Work only inside the current directory.
- Do not run git commands that change history, branches or remotes (commit, push, checkout, reset, rebase, stash). Reading with git status, git diff and git log is fine.
- Follow the conventions of the existing code: module layout, moduledoc and @doc style, typespecs, test style. lib/codex_wrapper/structured.ex owns a temporary --output-schema file and is the model for owning a temporary file.
- Before finishing, run these and fix what they report: mix format, mix compile --warnings-as-errors, mix credo --strict, mix test. Run mix dialyzer if it completes without network.
- Finish with a summary: files changed, the public API added, tests added, the exact check commands you ran with their results, and anything in the acceptance list you did not do, with the reason.

The issue follows.

# feat: read the --output-last-message file back for the caller

`Exec`, `ExecResume`, `ExecFork` and `Review` can set `-o, --output-last-message <FILE>` ("Specifies file where the last message from the agent should be written"), but nothing in the wrapper reads the file: the caller picks a path, reads it and removes it. In legacy `execute/2` stderr is merged into stdout (lib/codex_wrapper/config.ex:190), so in a plain-text run `result.stdout` holds whatever codex wrote to either stream.

| Caller wants | Before | After |
|---|---|---|
| The final agent message from a plain-text run | parse merged output, or manage a file path by hand | `CodexWrapper.LastMessage.run/3` returns it |
| No leftover files | caller removes the file | the wrapper owns a temp file and removes it after exit |

## API sketch

```elixir
{:ok, text, %CodexWrapper.Result{}} =
  Exec.new("summarize the diff in one paragraph")
  |> CodexWrapper.LastMessage.run(config)
```

## Acceptance

- [ ] Works with `Exec`, `ExecResume`, `ExecFork` and `Review`; an explicit `output_last_message/2` path stays the caller's, as today.
- [ ] The temp file is created with mode 0600 in `System.tmp_dir!/0` and removed after the process exits, on success, failure or raise, as `CodexWrapper.Structured` does for the schema file.
- [ ] Exit 0 with a missing or empty file returns `{:error, {:no_last_message, result}}`; a non-zero exit returns the result and whatever the file holds.
- [ ] Fake-executable tests that write the `-o` path. What codex writes when a turn fails was not checked here (it needs a model turn); record it from one native run.

## Related

- `CodexWrapper.Structured` (lib/codex_wrapper/structured.ex) owns the `--output-schema` file the same way.

Versions: codex_wrapper 0.8.1 (code at 7f472e6), codex-cli 0.165.0.

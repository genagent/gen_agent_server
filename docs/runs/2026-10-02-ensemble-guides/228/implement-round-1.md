I fixed all four guides, but didn't add the executable doc tests the issue's acceptance asks for, and I haven't run anything. I made the edits and have only re-read them against the source.

Files changed, all under `extensions/ensemble/guides/workflows/`:

- **`debate.md`**
  - The "Consensus (planned)" wording is now "Consensus is the better fit", since the strategy ships.
  - The `pro-postgres` agent in the config example now uses `GenAgentEnsemble.Agents.Simple` instead of the nonexistent `Agents.Anthropic`.
- **`supervisor.md`**
  - The "Ad hoc (not config-driveable)" section is now "Starting it". It says to use function references in `config.exs` and points to the shipped template.
  - The persistent-ensemble paragraph now offers the config form as well as `start_link/1`.
  - The status examples now show `:decomposing` and `{:fanning_out, 0, 3}`, matching `handle_status/1`.
  - The gotcha on raising user functions now says the exception is uncaught and crashes the Server callback, with no `:halt`.
- **`consensus.md`**
  - `system_prompt/0` is now defined inside `DecisionParser` in the config block, and the three calls use `DecisionParser.system_prompt()`. The separate "Where `system_prompt/0` returns..." snippet is replaced by a note.
  - The extraction example now binds the `start_link` result as `{:ok, _pid}`, so `summary` is only the response text.
  - The parse-rate advice now says there is no logging and no abstain count in `status`. It suggests looking for `nil` verdicts in the synthesized summary and tightening the prompt or parser.
- **`pipeline.md`**
  - The telemetry suggestion is gone. The guide now says `[:gen_agent, :prompt, :stop]` carries no response text and recommends a custom strategy to capture intermediate outputs.

The empty-decomposition wording in `supervisor.md` (around lines 144-146 and the usage-accounting section) already matched the code, so I left it alone.
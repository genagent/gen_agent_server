# Run 40: three claimed issues through a mixed-provider server batch

The literal control script is [040-control.exs](040-control.exs). It ran from
the server checkout against a clean gen_agent clone at `03fcc02`, after
`status/in-progress` was applied to core #248, core #242, and Ensemble #173.
The script used two named instances joined under `Task.Supervisor`:

| Instance | Pattern and worker limit | Task | Requested provider/model | Result |
| --- | --- | --- | --- | --- |
| `batch02-1218/codex` | Pool, two read-only workers | #248 release compatibility; #173 Supervisor subtask synthesis | Codex CLI default; actual model not captured by this `Run` report | Both confirmed, 76.7 seconds for the batch |
| `batch02-1218/claude` | Solo, plan mode | #242 caller-owned retry design | Claude `opus`; actual model not captured by this `Run` report | Confirmed, 99.7 seconds |

The script records the exact task prompts, role instructions, permissions,
timeout, result fields, and `after` cleanup. Both `Run.run/3` calls completed;
the caller stopped both instances. The Codex CLI emitted local MCP connection
warnings, but its two results completed. Source locations and compatibility
claims were checked independently before changes were made.

The bounded Ensemble change became merged [core PR #323](https://github.com/genagent/gen_agent/pull/323),
with 149 tests, format, Credo, Dialyzer, docs, and full CI. The compatible
CLI/Ensemble requirement slice became merged [core PR #327](https://github.com/genagent/gen_agent/pull/327),
and the runnable server requirement became merged [server PR #45](https://github.com/genagent/gen_agent_server/pull/45).
Core #248 stays open for Anthropic/OpenAI requirements and clean Hex resolution
after 0.7.0 publication. The risky #242 proceeded through run 41.

The Pool workers' responses contained progress preambles despite a requested
verdict line. Treat that as output-format behavior, not a source finding;
parse verdicts defensively. `Run` retained terminal text and usage but no
session ID for reading the actual CLI model. A future control API should
record the model and stage evidence directly, rather than inferring it from
the caller's requested alias.

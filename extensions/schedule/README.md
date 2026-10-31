# gen_agent_server schedule extension

Optional calendar jobs for [gen_agent_server](../../README.md), run by Quantum.
Listing the extension reads `jobs` from the server configuration file, adds the
`jobs` and `run_job` operations to `GenAgentServer.Ops`, and adds the `jobs`,
`job NAME`, and `run-job NAME` CLI commands.

```elixir
# mix.exs
{:gen_agent_server_schedule, path: "path/to/gen_agent_server/extensions/schedule"}

# config/config.exs
config :gen_agent_server, extensions: [GenAgentServer.Schedule]
```

## Jobs

The same JSON file may define Quantum jobs. No jobs run unless configured;
Oban, a database, and workers are not required. A job names an instance and
agent, a cron expression or alias such as `@hourly` or `@daily`, and exactly
one `prompt` or `prompt_file`. A prompt file is read for each run, so editing
it changes the next task without restarting the server.

```json
{
  "profiles": [
    {"name": "home", "cwd": "/path/to/project", "providers": ["codex"]}
  ],
  "jobs": [
    {"name": "daily-review", "instance": "home", "agent": "codex",
     "schedule": "@daily", "prompt_file": "daily-review.md", "overlap": false}
  ]
}
```

```sh
mix gen_agent_server.remote jobs
mix gen_agent_server.remote run-job daily-review
mix gen_agent_server.remote job daily-review
mix gen_agent_server.remote --instance home result INVOCATION_ID
```

`run-job` queues one immediate run, and `job NAME` returns its latest admitted
invocation ID or `never run`. Poll `job NAME` after queuing if the ID is not
available yet. The default `overlap: false` skips another run while the first
agent turn is active; set `overlap: true` only when parallel turns are wanted.
Jobs run on the local node. Scheduler restarts do not replay missed runs,
and results remain subject to the instance's bounded, process-local retention.
Invalid cron expressions fail configuration loading with the job name and file
path.
An admission rejection or prompt-file read failure has no invocation ID;
inspect Quantum job telemetry for that run. Admission rejections also emit
the server's usual rejection event with `source: :scheduler`. Turns with a known
invocation ID can be cancelled through Ops, remote CLI, MCP, or the Elixir API below. Start with read-only
jobs and review their results.

defmodule GenAgentServer.MCP.Resources.Quickstart do
  @moduledoc false

  use Snodo.Resource.Simple,
    uri: "gen-agent://guide/quickstart",
    name: "gen_agent_quickstart",
    description: "How to create Claude and Codex routes and retrieve their work",
    mime_type: "text/markdown"

  @guide """
  # GenAgent Server MCP quickstart

  This connection owns one running GenAgent Server process. Instances, provider
  sessions, invocation IDs, and results are shared by tools on this connection;
  they disappear when its stdio process exits. A second MCP connection starts
  a separate server. There is no cross-client mailbox or durable job store.

  1. Call `instances` to find existing instances. Call `describe_instance` to
     inspect routes and limits. The default instance is always present, but
     routes configured at startup only expose their names here.
  2. Call `create_instance` to make a named switchboard. For example:

     {"instance":"project","config":{"cwd":"/absolute/project/path",
      "max_in_flight":3,"routes":[
      {"name":"planner","provider":"claude","model":"sonnet","effort":"medium"},
      {"name":"reviewer","provider":"codex","model":"gpt-5-codex","effort":"high"}
      ]}}

     Providers are `echo`, `claude`, and `codex`. A CLI route requires an
     existing absolute `cwd`, inherited from the top-level config or set on
     that route. Omit `model` and `effort` for provider defaults. Use model IDs
     available to the installed CLI and account. Up to 16 routes are allowed.
     Configuration is immutable: create a new instance to change a model.
  3. Call `invoke` with `instance`, `agent` (the route name), and `prompt`.
     Keep the returned ID and poll `result` with the same instance. Reads are
     repeatable until the bounded result store evicts them. `ask` submits and
     waits when a synchronous turn is suitable. `status` reports in-flight
     work and queues.
  4. Call `stop_instance` when finished. This discards that instance's routes,
     sessions, and results. The default instance cannot be stopped.

  Claude defaults to `read_only`: its CLI runs in `dontAsk` mode with only
  Read, Grep, and Glob tools. `plan` is also available, but Claude CLI 2.1.284
  has ignored an explicit `--model` in plan mode in live tests. Codex defaults
  to a read-only sandbox, disabled approvals, and ignored user config. A route
  may explicitly set `claude_permission_mode` to `accept_edits`, `codex_sandbox` to
  `workspace_write`, or `codex_user_config` to `inherit`. These are provider
  controls, not a server-enforced filesystem boundary. Review edits before
  merging. `create_instance` does not itself run a model; `invoke` and `ask` do.

  The MCP surface is deliberately scoped to instance lifecycle, invocation,
  result reading, and status. Scheduling, Ensemble pattern execution, and
  session-to-session messaging are not exposed here.
  """

  @impl true
  def read(_params, _context), do: {:ok, @guide}
end

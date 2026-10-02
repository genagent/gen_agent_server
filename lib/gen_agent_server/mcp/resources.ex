defmodule GenAgentServer.MCP.Resources.Index do
  @moduledoc false

  use Snodo.Resource.Simple,
    uri: "gen-agent://guide/index",
    name: "gen_agent_guide_index",
    description: "Start here: the MCP tool catalogue and focused operating guides",
    mime_type: "text/markdown"

  @guide """
  # GenAgent Server guide index

  This MCP connection is a local GenAgent Server process. Its tools can create
  Claude, Codex, and Echo routes, run turns, and inspect results. Read the guide
  that matches the work before choosing a tool:

  - `gen-agent://guide/quickstart` — create a named instance and choose a
    provider, model, effort, project directory, and access mode.
  - `gen-agent://guide/invocations` — choose `ask` or `invoke` + `result`, inspect
    `status`, and keep invocation IDs with their instance names.
  - `gen-agent://guide/scope` — understand instance and result lifetime,
    provider sessions, and the boundary between MCP clients.
  - `gen-agent://guide/capabilities` — the exact MCP tools and the server APIs
    that are not available through this connection.

  Start with `instances`, then `describe_instance` for a known instance.
  `create_instance` only configures routes; `ask` and `invoke` start model work.
  The resources are operating guidance. Reading one does not change server
  state, grant access, or activate an agent skill.
  """

  @impl true
  def read(_params, _context), do: {:ok, @guide}
end

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
  session references, invocation IDs, and results are shared by tools on this
  connection; the server's state disappears when its stdio process exits. A
  second MCP connection starts a separate server. There is no cross-client
  mailbox or durable job store.

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

defmodule GenAgentServer.MCP.Resources.Invocations do
  @moduledoc false

  use Snodo.Resource.Simple,
    uri: "gen-agent://guide/invocations",
    name: "gen_agent_invocations",
    description: "Choose synchronous or asynchronous turns and inspect their results",
    mime_type: "text/markdown"

  @guide """
  # Running a turn

  Choose a route with `instances` and `describe_instance`. Use `ask` for a
  bounded turn when waiting for the result in one tool call is acceptable.
  `ask` accepts an optional `timeout_ms`; a timeout does not establish that
  the provider turn was cancelled.

  For longer work, call `invoke` with `instance`, `agent`, and `prompt`. Save
  the returned invocation ID together with its instance name. Call `result`
  with both values until its status is `completed` or `failed`; `pending`
  means the turn has not finished. Completed result reads are repeatable until
  the bounded result store evicts them. `status` reports current in-flight
  work and queues, but it is not a replacement for reading a result.

  A provider response can include a provider session ID. It is not a server
  invocation ID and is not an address for sending messages to an existing
  native Claude or Codex UI session. Check code and test results yourself
  before treating an agent's completion text as verified work.
  """

  @impl true
  def read(_params, _context), do: {:ok, @guide}
end

defmodule GenAgentServer.MCP.Resources.Scope do
  @moduledoc false

  use Snodo.Resource.Simple,
    uri: "gen-agent://guide/scope",
    name: "gen_agent_scope",
    description: "Understand instances, provider routes, and volatile state",
    mime_type: "text/markdown"

  @guide """
  # Instance and connection scope

  This stdio MCP connection starts one GenAgent Server VM. Its named instances,
  routes, provider session references, invocation IDs, and results live only in
  that VM. A second MCP connection starts a separate VM and cannot inspect or
  resume this connection's results. Ending this connection discards its state.

  The default instance is configured by server environment at startup and
  cannot be stopped. `create_instance` adds a named instance with fixed routes
  and limits. `describe_instance` reports its routes, selected model and
  effort, project directory, access settings, and limits. To change a route,
  stop that named instance and create another; stopping discards its results.
  A route's model string is passed to the installed provider CLI; the server
  cannot guarantee that every CLI or account accepts it.

  Project profiles and scheduled jobs are server configuration concepts.
  They are not editable through this MCP connection. The Elixir API and the
  server operations CLI have a broader control surface, but they do not share
  this stdio VM's state unless they run in that same process.
  """

  @impl true
  def read(_params, _context), do: {:ok, @guide}
end

defmodule GenAgentServer.MCP.Resources.Capabilities do
  @moduledoc false

  use Snodo.Resource.Simple,
    uri: "gen-agent://guide/capabilities",
    name: "gen_agent_capabilities",
    description: "Exact MCP allowlist and features available only in other APIs",
    mime_type: "text/markdown"

  @guide """
  # MCP capabilities and limits

  This connection exposes nine tools: `instances`, `agents`, `status`,
  `create_instance`, `describe_instance`, `stop_instance`, `ask`, `invoke`, and
  `result`. Only `create_instance`, `stop_instance`, `ask`, and `invoke` change
  runtime state or start work. Tool schemas specify accepted arguments.

  The server also has Elixir and CLI operations for scheduled jobs and
  Ensemble patterns. This MCP adapter does not expose `jobs`, `run_job`,
  `patterns`, or `run_pattern`; reading this guide does not make them callable.
  It does not offer cancellation, durable results, cross-client sharing,
  dynamic schedule edits, native-session messaging, or a dashboard. Do not
  infer those capabilities from the underlying OTP or wrapper libraries.

  A created Claude route defaults to restricted read tools; a created Codex
  route defaults to a read-only sandbox. The caller must explicitly request
  edit access. These provider controls do not replace host filesystem
  permissions or review of generated changes.
  """

  @impl true
  def read(_params, _context), do: {:ok, @guide}
end

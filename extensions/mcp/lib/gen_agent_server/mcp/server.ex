defmodule GenAgentServer.MCP.Server do
  @moduledoc false

  # The stdio MCP server. Tools and the guides for extension tools depend on the
  # configured extensions, so they are added to the router when the runtime is
  # built; the base guides are registered at compile time.

  alias GenAgentServer.MCP.{Resources, Tools}

  defmodule Base do
    @moduledoc false
    # The server's version, fixed at compile time so releases, which do not
    # ship Mix, advertise it too.
    @version GenAgentServer.MCP.base_version()

    use Snodo.Server,
      name: "gen-agent-server",
      version: @version,
      protocols: [
        Snodo.Protocol.V2026_07_28,
        Snodo.Protocol.V2025_11_25,
        Snodo.Protocol.V2025_06_18
      ]

    resource(Resources.Index)
    resource(Resources.Quickstart)
    resource(Resources.Invocations)
    resource(Resources.Scope)
    resource(Resources.Capabilities)
  end

  @doc "Immutable Snodo runtime for the tools available in this VM."
  def runtime(overrides \\ []) do
    tools = GenAgentServer.MCP.tools()

    router =
      Enum.reduce(Tools.modules(), Base.router(), &Snodo.Router.register_tool(&2, &1))

    router =
      [{"public_revision", Resources.PublicSource}, {"discover_peers", Resources.Peers}]
      |> Enum.filter(fn {tool, _resource} -> tool in tools end)
      |> Enum.reduce(router, fn {_tool, resource}, router ->
        Snodo.Router.register_resource(router, resource)
      end)

    Base.runtime(Keyword.merge([router: router, instructions: instructions(tools)], overrides))
  end

  defp instructions(tools) do
    Enum.join(
      [
        "GenAgent Server runs Claude, Codex, and Echo routes in named instances.",
        "Read gen-agent://guide/index for focused operating guides.",
        "Use instances and describe_instance to inspect state; create_instance to select " <>
          "providers, models, and project directories; invoke then result for long turns."
      ] ++
        if("public_revision" in tools,
          do: [
            "Use public_revision, public_file, public_issues, and public_issue for current public GitHub context."
          ],
          else: []
        ) ++
        if("discover_peers" in tools,
          do: [
            "Read gen-agent://guide/peers for opt-in existing-session discover/bind/send/result operations."
          ],
          else: []
        ) ++
        ["Instances and results belong to this MCP process and disappear when it exits."],
      " "
    )
  end
end

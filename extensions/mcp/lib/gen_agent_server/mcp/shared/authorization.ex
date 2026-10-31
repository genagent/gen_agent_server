defmodule GenAgentServer.MCP.Shared.Authorization do
  @moduledoc false
  @behaviour Snodo.Authorization

  @impl true
  def authorize(phase, component, context, %{instances: instances}) do
    trusted? = context.auth == %{shared_mcp: true, instances: instances}

    arguments =
      case context.request_params do
        %{"arguments" => args} when is_map(args) -> args
        _ -> %{}
      end

    scoped? =
      phase == :discovery or component.name == "instances" or
        arguments["instance"] in instances

    if trusted? and component.kind == :tool and
         component.name in GenAgentServer.MCP.Shared.tools() and scoped?,
       do: :ok,
       else: {:error, Snodo.Error.authorization(-32003, "Not authorized")}
  end
end

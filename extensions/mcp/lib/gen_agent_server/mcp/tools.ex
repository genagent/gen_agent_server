defmodule GenAgentServer.MCP.Tools do
  @moduledoc false

  # Snodo registers tools as modules. Operations come from GenAgentServer.Ops,
  # which includes whatever extensions are configured, so the tool modules are
  # generated from the catalogue the first time they are needed rather than
  # written by hand. Each module is named after its operation, for example
  # GenAgentServer.MCP.Tools.CreateInstance, and is created at most once per VM.

  alias GenAgentServer.Ops

  @doc "Tool modules for every operation `GenAgentServer.MCP.tools/0` exposes."
  def modules do
    :global.trans({__MODULE__, :define}, fn ->
      for name <- GenAgentServer.MCP.tools() do
        {:ok, op} = Ops.fetch(name)
        define(op)
      end
    end)
  end

  defp define(op) do
    module = Module.concat(__MODULE__, Macro.camelize(op.name))

    unless Code.ensure_loaded?(module) do
      contents =
        quote do
          @moduledoc false
          use Snodo.Tool, name: unquote(op.name), description: unquote(op.summary)

          input_schema(unquote(Macro.escape(Ops.json_schema(op))))

          @impl true
          def call(args, _context), do: GenAgentServer.MCP.run(unquote(op.name), args)
        end

      {:module, ^module, _binary, _} =
        Module.create(module, contents, Macro.Env.location(__ENV__))
    end

    module
  end
end

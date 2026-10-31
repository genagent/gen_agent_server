defmodule GenAgentServer.Extension do
  @moduledoc """
  Behaviour for optional layers above the base server.

  The base application drives agents: instances, invocations, results, the
  operation catalogue, the CLI, and release rpc. Everything else is an
  extension, listed in application configuration:

      config :gen_agent_server, extensions: [GenAgentServer.Schedule]

  With no extensions configured, the application starts only the base
  supervision tree and `GenAgentServer.Ops` contains only base operations.

  All callbacks are optional:

    * `operations/0` -- `GenAgentServer.Ops.Op` entries merged into the
      catalogue, so the CLI, rpc, and any other adapter over `Ops` see them.
      A name that is already taken raises when the catalogue is built.
    * `children/1` -- child specs started under the application supervisor
      after the instances. The argument holds `:instances`, a map of instance
      name to route names, and `:profile_file`, the configured file or `nil`.
    * `cli/2` -- extra CLI commands. Return `:unhandled` for arguments the
      extension does not own.
  """

  @type context :: [instances: %{String.t() => [String.t()]}, profile_file: String.t() | nil]

  @callback operations() :: [GenAgentServer.Ops.Op.t()]
  @callback children(context()) :: [Supervisor.child_spec() | {module(), term()} | module()]
  @callback cli(args :: [String.t()], source :: atom()) ::
              {:ok, String.t()} | {:error, term()} | :unhandled

  @optional_callbacks operations: 0, children: 1, cli: 2

  @doc "Configured extension modules, in configuration order."
  @spec configured() :: [module()]
  def configured, do: Application.get_env(:gen_agent_server, :extensions, [])

  @doc false
  def operations do
    for extension <- configured(),
        exports?(extension, :operations, 0),
        op <- extension.operations(),
        do: op
  end

  @doc false
  def children(context) do
    for extension <- configured(),
        exports?(extension, :children, 1),
        child <- extension.children(context),
        do: child
  end

  @doc false
  def cli(args, source) do
    Enum.reduce_while(configured(), :unhandled, fn extension, :unhandled ->
      if exports?(extension, :cli, 2) do
        case extension.cli(args, source) do
          :unhandled -> {:cont, :unhandled}
          result -> {:halt, result}
        end
      else
        {:cont, :unhandled}
      end
    end)
  end

  defp exports?(module, function, arity) do
    case Code.ensure_loaded(module) do
      {:module, ^module} -> function_exported?(module, function, arity)
      {:error, reason} -> raise ArgumentError, "extension #{inspect(module)} #{reason}"
    end
  end
end

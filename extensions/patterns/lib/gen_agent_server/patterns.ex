defmodule GenAgentServer.Patterns do
  @moduledoc """
  Optional Ensemble pattern runs from JSON specs.

  An optional `GenAgentServer.Extension`: listing it adds the `patterns` and
  `run_pattern` operations to `GenAgentServer.Ops`. `GenAgentServer.PatternSpec`
  turns a JSON-safe spec into an Ensemble strategy, `GenAgentServer.Run` runs it
  in a temporary instance, and `mix gen_agent_server.run` runs a spec file.

  Pattern instances started directly with
  `GenAgentServer.start_pattern_instance/5` are part of the base server and do
  not need this extension.
  """

  @behaviour GenAgentServer.Extension

  alias GenAgentServer.Ops
  import Ops, only: [op: 5, req: 3, opt: 3]

  @impl GenAgentServer.Extension
  def operations do
    [
      op("patterns", "List the pattern names that run_pattern accepts.", false, [], fn _ ->
        {:ok, %{patterns: GenAgentServer.PatternSpec.patterns()}}
      end),
      op(
        "run_pattern",
        "Run an Ensemble pattern spec in a temporary instance and return every result.",
        true,
        [
          req("spec", :object, "Pattern spec (see GenAgentServer.PatternSpec)"),
          req("prompts", :string_list, "Prompts, submitted together"),
          opt("cwd", :string, "Project directory for CLI providers"),
          opt("to", :string, "Route for switchboard specs"),
          opt("timeout_ms", :integer, "Wait limit for all results (default 600000)")
        ],
        fn a ->
          opts =
            [cwd: a["cwd"] && Path.expand(a["cwd"]), to: a["to"], timeout: a["timeout_ms"]]
            |> Enum.reject(fn {_k, v} -> is_nil(v) end)

          with {:ok, report} <- GenAgentServer.Run.run(a["spec"], a["prompts"], opts),
               do: {:ok, Ops.jsonable(report)}
        end
      )
    ]
  end
end

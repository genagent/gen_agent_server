defmodule GenAgentServer.MCP.Shared.Tools do
  @moduledoc false

  defmodule Instances do
    @moduledoc false
    use Snodo.Tool, name: "instances", description: "Instances for allowed startup instances."

    schema = GenAgentServer.Ops.json_schema(elem(GenAgentServer.Ops.fetch("instances"), 1))
    input_schema(schema)

    @impl true
    def call(args, context), do: GenAgentServer.MCP.Shared.run("instances", args, context)
  end

  defmodule Agents do
    @moduledoc false
    use Snodo.Tool, name: "agents", description: "Agents for allowed startup instances."

    schema = GenAgentServer.Ops.json_schema(elem(GenAgentServer.Ops.fetch("agents"), 1))
    schema = Map.update!(schema, "required", &Enum.uniq(["instance" | &1]))

    schema =
      put_in(schema, ["properties", "instance", "description"], "Explicit allowed instance name")

    input_schema(schema)

    @impl true
    def call(args, context), do: GenAgentServer.MCP.Shared.run("agents", args, context)
  end

  defmodule Status do
    @moduledoc false
    use Snodo.Tool, name: "status", description: "Status for allowed startup instances."

    schema = GenAgentServer.Ops.json_schema(elem(GenAgentServer.Ops.fetch("status"), 1))
    schema = Map.update!(schema, "required", &Enum.uniq(["instance" | &1]))

    schema =
      put_in(schema, ["properties", "instance", "description"], "Explicit allowed instance name")

    input_schema(schema)

    @impl true
    def call(args, context), do: GenAgentServer.MCP.Shared.run("status", args, context)
  end

  defmodule DescribeInstance do
    @moduledoc false
    use Snodo.Tool,
      name: "describe_instance",
      description: "Describe instance for allowed startup instances."

    schema =
      GenAgentServer.Ops.json_schema(elem(GenAgentServer.Ops.fetch("describe_instance"), 1))

    schema = Map.update!(schema, "required", &Enum.uniq(["instance" | &1]))

    schema =
      put_in(schema, ["properties", "instance", "description"], "Explicit allowed instance name")

    input_schema(schema)

    @impl true
    def call(args, context), do: GenAgentServer.MCP.Shared.run("describe_instance", args, context)
  end

  defmodule Invoke do
    @moduledoc false
    use Snodo.Tool, name: "invoke", description: "Invoke for allowed startup instances."

    schema = GenAgentServer.Ops.json_schema(elem(GenAgentServer.Ops.fetch("invoke"), 1))
    schema = Map.update!(schema, "required", &Enum.uniq(["instance" | &1]))

    schema =
      put_in(schema, ["properties", "instance", "description"], "Explicit allowed instance name")

    input_schema(schema)

    @impl true
    def call(args, context), do: GenAgentServer.MCP.Shared.run("invoke", args, context)
  end

  defmodule Result do
    @moduledoc false
    use Snodo.Tool, name: "result", description: "Result for allowed startup instances."

    schema = GenAgentServer.Ops.json_schema(elem(GenAgentServer.Ops.fetch("result"), 1))
    schema = Map.update!(schema, "required", &Enum.uniq(["instance" | &1]))

    schema =
      put_in(schema, ["properties", "instance", "description"], "Explicit allowed instance name")

    input_schema(schema)

    @impl true
    def call(args, context), do: GenAgentServer.MCP.Shared.run("result", args, context)
  end

  defmodule Ask do
    @moduledoc false
    use Snodo.Tool,
      name: "ask",
      description: "Submit and wait up to 5000 ms; returns a pollable ID even when pending."

    schema = GenAgentServer.Ops.json_schema(elem(GenAgentServer.Ops.fetch("ask"), 1))
    schema = Map.update!(schema, "required", &Enum.uniq(["instance" | &1]))

    schema =
      put_in(schema, ["properties", "instance", "description"], "Explicit allowed instance name")

    schema = put_in(schema, ["properties", "timeout_ms", "maximum"], 5000)

    schema =
      put_in(
        schema,
        ["properties", "timeout_ms", "description"],
        "Wait 0..5000 ms (default 1000)"
      )

    input_schema(schema)

    @impl true
    def call(args, context), do: GenAgentServer.MCP.Shared.run("ask", args, context)
  end
end

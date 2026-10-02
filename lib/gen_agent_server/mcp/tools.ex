defmodule GenAgentServer.MCP.Tools do
  @moduledoc false

  # The MCP catalogue is an allowlist of GenAgentServer.Ops operations. Each tool
  # names its operation literally; the schemas are checked against
  # GenAgentServer.Ops.json_schema/1 in the test suite.

  defmodule Instances do
    @moduledoc false
    use Snodo.Tool, name: "instances", description: "List running instances."

    input_schema(%{
      "type" => "object",
      "additionalProperties" => false,
      "properties" => %{},
      "required" => []
    })

    @impl true
    def call(arguments, _context), do: GenAgentServer.MCP.run("instances", arguments)
  end

  defmodule Agents do
    @moduledoc false
    use Snodo.Tool, name: "agents", description: "List the routes of an instance."

    input_schema(%{
      "type" => "object",
      "additionalProperties" => false,
      "properties" => %{
        "instance" => %{
          "type" => "string",
          "minLength" => 1,
          "description" => "Instance name (default: the default instance)"
        }
      },
      "required" => []
    })

    @impl true
    def call(arguments, _context), do: GenAgentServer.MCP.run("agents", arguments)
  end

  defmodule Status do
    @moduledoc false
    use Snodo.Tool,
      name: "status",
      description: "Ensemble status of an instance: in-flight work and queues."

    input_schema(%{
      "type" => "object",
      "additionalProperties" => false,
      "properties" => %{
        "instance" => %{
          "type" => "string",
          "minLength" => 1,
          "description" => "Instance name (default: the default instance)"
        }
      },
      "required" => []
    })

    @impl true
    def call(arguments, _context), do: GenAgentServer.MCP.run("status", arguments)
  end

  defmodule Invoke do
    @moduledoc false
    use Snodo.Tool, name: "invoke", description: "Submit a prompt and return its invocation ID."

    input_schema(%{
      "type" => "object",
      "additionalProperties" => false,
      "properties" => %{
        "instance" => %{
          "type" => "string",
          "minLength" => 1,
          "description" => "Instance name (default: the default instance)"
        },
        "agent" => %{"type" => "string", "minLength" => 1, "description" => "Route name"},
        "prompt" => %{"type" => "string", "minLength" => 1, "description" => "Prompt text"}
      },
      "required" => ["agent", "prompt"]
    })

    @impl true
    def call(arguments, _context), do: GenAgentServer.MCP.run("invoke", arguments)
  end

  defmodule Result do
    @moduledoc false
    use Snodo.Tool,
      name: "result",
      description: "Read an invocation result. Repeatable until evicted."

    input_schema(%{
      "type" => "object",
      "additionalProperties" => false,
      "properties" => %{
        "instance" => %{
          "type" => "string",
          "minLength" => 1,
          "description" => "Instance name (default: the default instance)"
        },
        "id" => %{"type" => "string", "minLength" => 1, "description" => "Invocation ID"}
      },
      "required" => ["id"]
    })

    @impl true
    def call(arguments, _context), do: GenAgentServer.MCP.run("result", arguments)
  end

  defmodule Ask do
    @moduledoc false
    use Snodo.Tool, name: "ask", description: "Submit a prompt and wait for its result."

    input_schema(%{
      "type" => "object",
      "additionalProperties" => false,
      "properties" => %{
        "instance" => %{
          "type" => "string",
          "minLength" => 1,
          "description" => "Instance name (default: the default instance)"
        },
        "agent" => %{"type" => "string", "minLength" => 1, "description" => "Route name"},
        "prompt" => %{"type" => "string", "minLength" => 1, "description" => "Prompt text"},
        "timeout_ms" => %{
          "type" => "integer",
          "minimum" => 0,
          "description" => "Stop waiting after this many milliseconds"
        }
      },
      "required" => ["agent", "prompt"]
    })

    @impl true
    def call(arguments, _context), do: GenAgentServer.MCP.run("ask", arguments)
  end

  # The lifecycle tools take their schema from the operation itself, so the
  # nested creation config cannot drift from GenAgentServer.Ops.

  defmodule CreateInstance do
    @moduledoc false
    use Snodo.Tool,
      name: "create_instance",
      description:
        "Create a named instance with one or more provider routes (echo, claude, codex). " <>
          "Configuration is fixed at creation and held only in memory. Nothing runs until a prompt is submitted."

    input_schema(
      "create_instance"
      |> GenAgentServer.Ops.fetch()
      |> elem(1)
      |> GenAgentServer.Ops.json_schema()
    )

    @impl true
    def call(arguments, _context), do: GenAgentServer.MCP.run("create_instance", arguments)
  end

  defmodule DescribeInstance do
    @moduledoc false
    use Snodo.Tool,
      name: "describe_instance",
      description:
        "Describe an instance: routes with provider, model, effort, and access mode, plus limits."

    input_schema(
      "describe_instance"
      |> GenAgentServer.Ops.fetch()
      |> elem(1)
      |> GenAgentServer.Ops.json_schema()
    )

    @impl true
    def call(arguments, _context), do: GenAgentServer.MCP.run("describe_instance", arguments)
  end

  defmodule StopInstance do
    @moduledoc false
    use Snodo.Tool,
      name: "stop_instance",
      description:
        "Stop a runtime instance (not the default instance). Its routes and stored results are discarded."

    input_schema(
      "stop_instance"
      |> GenAgentServer.Ops.fetch()
      |> elem(1)
      |> GenAgentServer.Ops.json_schema()
    )

    @impl true
    def call(arguments, _context), do: GenAgentServer.MCP.run("stop_instance", arguments)
  end
end

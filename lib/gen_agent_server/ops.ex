defmodule GenAgentServer.Ops do
  @moduledoc """
  Catalogue of server operations with JSON-safe inputs and outputs.

  Every operation takes a map with string keys and returns `{:ok, data}` or
  `{:error, %{code: String.t(), message: String.t()}}`, where `data` contains
  only maps, lists, strings, numbers, booleans, and nil. The CLI
  (`mix gen_agent_server.ops`), the release RPC path (`GenAgentServer.Ops.Remote`),
  and the MCP adapter (`GenAgentServer.MCP`) all call `call/3`, so each operation is defined once.

  The catalogue holds no state of its own. Every operation reads or changes the
  live instances, Ensemble sessions, and scheduler, so the direct Elixir API
  stays authoritative.

  Operations marked `mutates: true` start work or change running state.
  Adapters that expose operations to less trusted callers can filter on it.
  """

  alias GenAgentServer.{PatternSpec, Run}

  defmodule Op do
    @moduledoc false
    @enforce_keys [:name, :summary, :mutates, :params, :handler]
    defstruct [:name, :summary, :mutates, :params, :handler]
  end

  @type param_type :: :string | :integer | :object | :string_list

  @doc "All operations, sorted by name."
  def operations do
    [
      op("instances", "List running instances.", false, [], fn _ ->
        {:ok, %{instances: GenAgentServer.instances()}}
      end),
      op("agents", "List the routes of an instance.", false, [instance()], fn a ->
        with {:ok, routes} <- guarded(fn -> GenAgentServer.agents(a["instance"]) end),
             do: {:ok, %{instance: a["instance"], agents: routes}}
      end),
      op(
        "status",
        "Ensemble status of an instance: in-flight work and queues.",
        false,
        [instance()],
        fn a ->
          with {:ok, status} <- guarded(fn -> GenAgentServer.status(a["instance"]) end),
               do: {:ok, jsonable(status)}
        end
      ),
      op(
        "invoke",
        "Submit a prompt and return its invocation ID.",
        true,
        [instance(), req("agent", :string, "Route name"), req("prompt", :string, "Prompt text")],
        fn a ->
          with {:ok, id} <-
                 GenAgentServer.invoke(a["instance"], a["agent"], a["prompt"],
                   source: Map.get(a, :source, :api)
                 ),
               do: {:ok, %{instance: a["instance"], id: id}}
        end
      ),
      op(
        "result",
        "Read an invocation result. Repeatable until evicted.",
        false,
        [instance(), req("id", :string, "Invocation ID")],
        fn a -> result_data(a["id"], GenAgentServer.result(a["instance"], a["id"])) end
      ),
      op(
        "ask",
        "Submit a prompt and wait for its result.",
        true,
        [
          instance(),
          req("agent", :string, "Route name"),
          req("prompt", :string, "Prompt text"),
          opt("timeout_ms", :integer, "Stop waiting after this many milliseconds")
        ],
        fn a ->
          opts = [source: Map.get(a, :source, :api)]
          opts = if a["timeout_ms"], do: [{:timeout, a["timeout_ms"]} | opts], else: opts

          case GenAgentServer.ask_instance(a["instance"], a["agent"], a["prompt"], opts) do
            {:ok, response} -> {:ok, Map.put(response_data(response), :status, "completed")}
            error -> error
          end
        end
      ),
      op(
        "jobs",
        "List configured scheduled jobs with their latest invocation ID.",
        false,
        [],
        fn _ ->
          jobs =
            for name <- guarded_jobs() do
              {:ok, latest} = GenAgentServer.Dispatch.latest(name)
              %{name: name, latest: latest}
            end

          {:ok, %{jobs: jobs}}
        end
      ),
      op(
        "run_job",
        "Queue one immediate run of a scheduled job.",
        true,
        [req("name", :string, "Job name")],
        fn a ->
          case GenAgentServer.CLI.run(["run-job", a["name"]]) do
            {:ok, _} -> {:ok, %{name: a["name"], queued: true}}
            error -> error
          end
        end
      ),
      op("patterns", "List the pattern names that run_pattern accepts.", false, [], fn _ ->
        {:ok, %{patterns: PatternSpec.patterns()}}
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

          with {:ok, report} <- Run.run(a["spec"], a["prompts"], opts),
               do: {:ok, jsonable(report)}
        end
      ),
      op(
        "stop_instance",
        "Stop a runtime instance (not the default instance).",
        true,
        [req("instance", :string, "Instance name")],
        fn a ->
          with :ok <- GenAgentServer.stop_instance(a["instance"]),
               do: {:ok, %{instance: a["instance"], stopped: true}}
        end
      )
    ]
    |> Enum.sort_by(& &1.name)
  end

  @doc "Catalogue entries without handlers, for listing and help output."
  def list do
    Enum.map(operations(), fn op ->
      %{name: op.name, summary: op.summary, mutates: op.mutates, params: op.params}
    end)
  end

  def fetch(name) do
    case Enum.find(operations(), &(&1.name == name)) do
      nil -> {:error, error(:unknown_operation, "unknown operation: #{name}")}
      op -> {:ok, op}
    end
  end

  @doc "JSON Schema for an operation's arguments."
  def json_schema(%Op{params: params}) do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "properties" =>
        Map.new(params, fn p -> {p.name, Map.put(schema_type(p.type), "description", p.doc)} end),
      "required" => for(p <- params, p.required, do: p.name)
    }
  end

  @doc """
  Validate `args` and run the operation `name`.

  `opts` is trusted caller context, never client input. `:source` sets the
  telemetry source of `invoke` and `ask` (default `:api`).
  """
  @spec call(String.t(), map(), keyword()) ::
          {:ok, term()} | {:error, %{code: String.t(), message: String.t()}}
  def call(name, args \\ %{}, opts \\ [])
      when is_binary(name) and is_map(args) and is_list(opts) do
    with {:ok, op} <- fetch(name),
         {:ok, args} <- validate(op, args) do
      args = Map.put(args, :source, Keyword.get(opts, :source, :api))

      case op.handler.(args) do
        {:ok, data} -> {:ok, data}
        {:error, %{code: _, message: _} = e} -> {:error, e}
        {:error, reason} -> {:error, normalize(reason)}
      end
    end
  end

  # -- params ------------------------------------------------------------------

  defp op(name, summary, mutates, params, handler),
    do: %Op{name: name, summary: summary, mutates: mutates, params: params, handler: handler}

  defp req(name, type, doc), do: %{name: name, type: type, required: true, doc: doc}
  defp opt(name, type, doc), do: %{name: name, type: type, required: false, doc: doc}

  defp instance,
    do: %{
      name: "instance",
      type: :string,
      required: false,
      doc: "Instance name (default: the default instance)"
    }

  defp validate(op, args) do
    known = MapSet.new(op.params, & &1.name)

    case Enum.reject(Map.keys(args), &MapSet.member?(known, &1)) do
      [] ->
        Enum.reduce_while(op.params, {:ok, args}, fn p, {:ok, acc} ->
          case {Map.get(acc, p.name), p} do
            {nil, %{name: "instance"}} ->
              {:cont, {:ok, Map.put(acc, "instance", GenAgentServer.session_name())}}

            {nil, %{required: true}} ->
              {:halt, {:error, error(:invalid_args, "missing required argument: #{p.name}")}}

            {nil, _} ->
              {:cont, {:ok, acc}}

            {value, _} ->
              if type?(p.type, value),
                do: {:cont, {:ok, acc}},
                else:
                  {:halt,
                   {:error,
                    error(:invalid_args, "argument #{p.name} must be #{type_name(p.type)}")}}
          end
        end)

      unknown ->
        {:error, error(:invalid_args, "unknown arguments: #{Enum.join(unknown, ", ")}")}
    end
  end

  defp type?(:string, v), do: is_binary(v) and v != ""
  defp type?(:integer, v), do: is_integer(v) and v >= 0
  defp type?(:object, v), do: is_map(v)
  defp type?(:string_list, v), do: is_list(v) and v != [] and Enum.all?(v, &is_binary/1)

  defp type_name(:string), do: "a non-empty string"
  defp type_name(:integer), do: "a non-negative integer"
  defp type_name(:object), do: "an object"
  defp type_name(:string_list), do: "a non-empty list of strings"

  defp schema_type(:string), do: %{"type" => "string", "minLength" => 1}
  defp schema_type(:integer), do: %{"type" => "integer", "minimum" => 0}
  defp schema_type(:object), do: %{"type" => "object"}

  defp schema_type(:string_list),
    do: %{"type" => "array", "items" => %{"type" => "string"}, "minItems" => 1}

  # -- results -----------------------------------------------------------------

  defp result_data(id, {:ok, :pending}), do: {:ok, %{id: id, status: "pending"}}

  defp result_data(id, {:ok, :completed, response}),
    do: {:ok, response |> response_data() |> Map.merge(%{id: id, status: "completed"})}

  defp result_data(id, {:ok, :failed, reason}),
    do: {:ok, %{id: id, status: "failed", error: normalize(reason)}}

  defp result_data(_id, error), do: error

  defp response_data(response) do
    %{
      text: response.text,
      usage: jsonable(Map.get(response, :usage)),
      session_id: Map.get(response, :session_id),
      duration_ms: Map.get(response, :duration_ms)
    }
  end

  # Status calls can race with instance shutdown (genagent/gen_agent_server#26).
  defp guarded(fun) do
    fun.()
  catch
    :exit, {:noproc, _} -> {:error, :instance_not_found}
  end

  defp guarded_jobs do
    GenAgentServer.Dispatch.jobs()
  catch
    :exit, {:noproc, _} -> []
  end

  # -- errors and encoding -----------------------------------------------------

  defp error(code, message), do: %{code: Atom.to_string(code), message: message}

  @doc false
  def normalize(reason) when is_atom(reason), do: error(reason, Atom.to_string(reason))

  def normalize({kind, detail}) when is_atom(kind),
    do: error(kind, "#{kind}: #{inspect(detail, printable_limit: 500)}")

  def normalize(reason), do: error(:error, inspect(reason, printable_limit: 500))

  @doc "Convert a term to JSON-safe data: atoms become strings, tuples lists."
  def jsonable(nil), do: nil
  def jsonable(v) when is_boolean(v) or is_number(v) or is_binary(v), do: v

  def jsonable(v) when is_atom(v),
    do: v |> Atom.to_string() |> String.replace_prefix("Elixir.", "")

  def jsonable(%_{} = struct), do: struct |> Map.from_struct() |> jsonable()

  def jsonable(v) when is_map(v),
    do: Map.new(v, fn {k, val} -> {jsonable_key(k), jsonable(val)} end)

  def jsonable(v) when is_list(v), do: Enum.map(v, &jsonable/1)
  def jsonable(v) when is_tuple(v), do: v |> Tuple.to_list() |> jsonable()
  def jsonable(v), do: inspect(v)

  defp jsonable_key(k) when is_binary(k), do: k
  defp jsonable_key(k) when is_atom(k), do: Atom.to_string(k)
  defp jsonable_key(k), do: inspect(k)
end

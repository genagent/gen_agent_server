defmodule GenAgentServer.Ops do
  @moduledoc """
  Catalogue of server operations with JSON-safe inputs and outputs.

  Every operation takes a map with string keys and returns `{:ok, data}` or
  `{:error, %{code: String.t(), message: String.t()}}`, where `data` contains
  only maps, lists, strings, numbers, booleans, and nil. The CLI
  (`mix gen_agent_server.ops`), the release RPC path (`GenAgentServer.Ops.Remote`),
  and adapters in extensions (such as MCP) all call `call/3`, so each operation is
  defined once. Extensions add operations through `GenAgentServer.Extension`.

  The catalogue holds no state of its own. Every operation reads or changes the
  live instances, Ensemble sessions, and scheduler, so the direct Elixir API
  stays authoritative.

  Operations marked `mutates: true` start work or change running state.
  Adapters that expose operations to less trusted callers can filter on it.
  """

  defmodule Op do
    @moduledoc false
    @enforce_keys [:name, :summary, :mutates, :params, :handler]
    defstruct [:name, :summary, :mutates, :params, :handler]

    @type t :: %__MODULE__{
            name: String.t(),
            summary: String.t(),
            mutates: boolean(),
            params: [map()],
            handler: (map() -> {:ok, term()} | {:error, term()})
          }
  end

  @type param_type :: :string | :integer | :object | :string_list

  @doc """
  All operations, base and configured extensions, sorted by name.

  Raises `ArgumentError` when two operations share a name.
  """
  def operations do
    ops = base_operations() ++ GenAgentServer.Extension.operations()
    names = Enum.map(ops, & &1.name)

    case names -- Enum.uniq(names) do
      [] ->
        Enum.sort_by(ops, & &1.name)

      dups ->
        raise ArgumentError, "duplicate operation names: #{Enum.join(Enum.uniq(dups), ", ")}"
    end
  end

  defp base_operations do
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
        "invocations",
        "Read content-free retained invocation summaries, newest admission first.",
        false,
        [
          req("instance", :string, "Instance name"),
          opt("limit", :integer, "Maximum entries (default 50, range 1..200)")
          |> Map.put(:schema, %{"minimum" => 1, "maximum" => 200})
        ],
        fn a ->
          opts = if Map.has_key?(a, "limit"), do: [limit: a["limit"]], else: []

          with {:ok, summaries} <- GenAgentServer.invocations(a["instance"], opts),
               do: {:ok, %{instance: a["instance"], invocations: jsonable(summaries)}}
        end
      ),
      op(
        "cancel",
        "Cancel one invocation without retrying. Acknowledgement does not prove provider cleanup.",
        true,
        [
          req("instance", :string, "Exact instance name"),
          req("id", :string, "Exact invocation ID")
        ],
        fn a ->
          with {:ok, ack} <- GenAgentServer.cancel(a["instance"], a["id"]),
               do: {:ok, %{instance: a["instance"], id: a["id"], status: Atom.to_string(ack)}}
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
        "stop_instance",
        "Stop a runtime instance (not the default instance). Its routes and stored results are discarded.",
        true,
        [req("instance", :string, "Instance name")],
        fn a ->
          with :ok <- GenAgentServer.stop_instance(a["instance"]),
               do: {:ok, %{instance: a["instance"], stopped: true}}
        end
      ),
      op(
        "create_instance",
        "Create a named instance with one or more provider routes (echo, claude, codex). " <>
          "Configuration is fixed at creation and held only in memory. Nothing runs until a prompt is submitted.",
        true,
        [
          req("instance", :string, "Name for the new instance"),
          "config"
          |> req(:object, "Switchboard configuration: routes, optional cwd and limits")
          |> Map.put(:schema, config_schema())
        ],
        fn a ->
          with {:ok, description} <-
                 GenAgentServer.create_instance(a["instance"], a["config"]),
               do: {:ok, jsonable(Map.put(description, :instance, a["instance"]))}
        end
      ),
      op(
        "describe_instance",
        "Describe an instance: routes with provider, model, effort, access mode, and response text selection, plus limits.",
        false,
        [instance()],
        fn a ->
          with {:ok, description} <- GenAgentServer.describe_instance(a["instance"]),
               do: {:ok, jsonable(Map.put(description, :instance, a["instance"]))}
        end
      )
    ]
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
        Map.new(params, fn p ->
          {p.name,
           p.type
           |> schema_type()
           |> Map.merge(Map.get(p, :schema, %{}))
           |> Map.put("description", p.doc)}
        end),
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
  #
  # The builders are public so extensions define operations the same way.

  @doc "Build an operation. `mutates` marks operations that start work or change state."
  @spec op(String.t(), String.t(), boolean(), [map()], (map() -> term())) :: Op.t()
  def op(name, summary, mutates, params, handler),
    do: %Op{name: name, summary: summary, mutates: mutates, params: params, handler: handler}

  @doc "A required parameter."
  @spec req(String.t(), param_type(), String.t()) :: map()
  def req(name, type, doc), do: %{name: name, type: type, required: true, doc: doc}

  @doc "An optional parameter."
  @spec opt(String.t(), param_type(), String.t()) :: map()
  def opt(name, type, doc), do: %{name: name, type: type, required: false, doc: doc}

  @doc "The optional `instance` parameter, defaulting to the default instance."
  @spec instance() :: map()
  def instance,
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
            {nil, %{name: "instance", required: false}} ->
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

  # Documents GenAgentServer.InstanceSpec for clients. The parser, not this
  # schema, is the authority: it rejects anything outside these keys.
  defp config_schema do
    bounds = GenAgentServer.InstanceSpec.bounds()
    name = %{"type" => "string", "pattern" => "^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$"}

    route = %{
      "type" => "object",
      "additionalProperties" => false,
      "properties" => %{
        "name" => Map.put(name, "description", "Route name, unique in the instance"),
        "provider" => %{"type" => "string", "enum" => GenAgentServer.Providers.names()},
        "model" => %{
          "type" => "string",
          "maxLength" => 128,
          "description" => "Model name (claude, codex). Omit for the provider default."
        },
        "effort" => %{
          "type" => "string",
          "enum" => Enum.map(GenAgentServer.Providers.efforts("claude"), &Atom.to_string/1),
          "description" =>
            "Reasoning effort. claude: low, medium, high, xhigh, max. codex: low, medium, high."
        },
        "cwd" => %{
          "type" => "string",
          "description" => "Absolute project directory. Defaults to the top-level cwd."
        },
        "claude_permission_mode" => %{
          "type" => "string",
          "enum" =>
            Enum.map(
              GenAgentServer.Providers.access_choices(:claude_permission_mode),
              &Atom.to_string/1
            ),
          "description" => "Defaults to inherit: omit server permission and tools overrides."
        },
        "codex_sandbox" => %{
          "type" => "string",
          "enum" =>
            Enum.map(GenAgentServer.Providers.access_choices(:codex_sandbox), &Atom.to_string/1),
          "description" => "Defaults to inherit: omit the sandbox override."
        },
        "codex_user_config" => %{
          "type" => "string",
          "enum" =>
            Enum.map(
              GenAgentServer.Providers.access_choices(:codex_user_config),
              &Atom.to_string/1
            ),
          "description" => "Defaults to inherit the server user CLI configuration."
        },
        "codex_response_text" => %{
          "type" => "string",
          "enum" => ["all_messages", "final_message"],
          "description" =>
            "Codex result text: join all messages (default), or use only the final message."
        }
      },
      "required" => ["name", "provider"]
    }

    %{
      "additionalProperties" => false,
      "properties" => %{
        "routes" => %{
          "type" => "array",
          "minItems" => 1,
          "maxItems" => bounds.max_routes,
          "items" => route
        },
        "cwd" => %{"type" => "string", "description" => "Absolute default project directory"},
        "max_in_flight" => %{
          "type" => "integer",
          "minimum" => 1,
          "maximum" => bounds.max_in_flight
        },
        "max_results" => %{"type" => "integer", "minimum" => 1, "maximum" => bounds.max_results}
      },
      "required" => ["routes"]
    }
  end

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

  # -- errors and encoding -----------------------------------------------------

  defp error(code, message), do: %{code: Atom.to_string(code), message: message}

  # Coarse `GenAgent.Backend.Error` kinds that may appear in public output.
  # The kind of a typed error is open-ended (adapters derive it from legacy
  # tuple tags), so anything outside this list is reported as `:unclassified`.
  @backend_error_kinds ~w(rate_limited authentication invalid_request server_error http_error
                          transport provider_error conversation_lost invalid_response timeout)a

  # `GenAgent.Backend.Error` retains provider bodies, headers, and message text
  # in `:raw` and `:message`. Public presentation reports only the allowlisted
  # kind and `:retryable?`; direct Elixir callers still receive the full struct.
  # The struct is matched as a tagged map so this module compiles against cores
  # that do not define it.
  @doc false
  def normalize(%{__struct__: GenAgent.Backend.Error} = reason),
    do: error(:backend_error, backend_error_message(reason))

  def normalize(reason), do: reason |> redact_backend_errors() |> present()

  @doc """
  Single-string presentation of a failure reason for public output.

  Used where a result carries its error as one string (`GenAgentServer.Run`
  items). A typed backend error becomes its coarse category. Any other reason
  keeps its plain `inspect/1` text, with nested typed errors replaced first.
  """
  @spec error_text(term()) :: String.t()
  def error_text(%{__struct__: GenAgent.Backend.Error} = reason),
    do: backend_error_message(reason)

  def error_text(reason), do: reason |> redact_backend_errors() |> inspect()

  defp present(reason) when is_atom(reason), do: error(reason, Atom.to_string(reason))

  defp present({:invalid_config, detail}) when is_binary(detail),
    do: error(:invalid_config, detail)

  defp present({kind, detail}) when is_atom(kind),
    do: error(kind, "#{kind}: #{inspect(detail, printable_limit: 500)}")

  defp present(reason), do: error(:error, inspect(reason, printable_limit: 500))

  defp backend_error_message(error) do
    kind = Map.get(error, :kind)
    kind = if kind in @backend_error_kinds, do: kind, else: :unclassified
    retry = if Map.get(error, :retryable?) == true, do: " (retryable)", else: ""
    "backend_error: #{kind}#{retry}"
  end

  # Replaces typed errors nested inside framework wrappers (stage tuples,
  # lists, maps) with a fixed marker before generic inspection. Nothing is
  # called and no atoms are made. A typed error is replaced as soon as it is
  # reached; its `:raw` is never traversed.
  #
  # The walk is bounded by fixed limits. A container that is deeper than
  # @redact_depth, or larger than the remaining @redact_nodes budget, is
  # replaced whole by @redacted rather than copied or left unexamined. Terms
  # within the limits come back unchanged unless they hold a typed error.
  @redact_depth 16
  @redact_nodes 1_000
  @redacted "<redacted>"

  defp redact_backend_errors(reason), do: reason |> redact(0, @redact_nodes) |> elem(0)

  defp redact(%{__struct__: GenAgent.Backend.Error} = reason, _depth, left) do
    kind = Map.get(reason, :kind)
    {{:backend_error, if(kind in @backend_error_kinds, do: kind, else: :unclassified)}, left}
  end

  defp redact(map, depth, left) when is_map(map) do
    size = map_size(map)

    if depth >= @redact_depth or size > left do
      {@redacted, left}
    else
      {pairs, left} =
        Enum.map_reduce(:maps.to_list(map), left - size, fn {key, value}, left ->
          {key, left} = redact(key, depth + 1, left)
          {value, left} = redact(value, depth + 1, left)
          {{key, value}, left}
        end)

      {Map.new(pairs), left}
    end
  end

  defp redact(tuple, depth, left) when is_tuple(tuple) do
    size = tuple_size(tuple)

    if depth >= @redact_depth or size > left do
      {@redacted, left}
    else
      {elements, left} =
        Enum.map_reduce(Tuple.to_list(tuple), left - size, &redact(&1, depth + 1, &2))

      {List.to_tuple(elements), left}
    end
  end

  defp redact([_ | _] = list, depth, left) do
    if depth >= @redact_depth, do: {@redacted, left}, else: redact_list(list, depth, left)
  end

  defp redact(term, _depth, left), do: {term, left}

  # List cells share the list's depth; each cell costs one node.
  defp redact_list([head | tail], depth, left) when left > 0 do
    {head, left} = redact(head, depth + 1, left - 1)
    {tail, left} = redact_list(tail, depth, left)
    {[head | tail], left}
  end

  defp redact_list([_ | _], _depth, left), do: {@redacted, left}
  defp redact_list(tail, depth, left), do: redact(tail, depth + 1, left)

  @doc "Convert a term to JSON-safe data: atoms become strings, tuples lists."
  def jsonable(nil), do: nil
  def jsonable(v) when is_boolean(v) or is_number(v) or is_binary(v), do: v

  def jsonable(v) when is_atom(v),
    do: v |> Atom.to_string() |> String.replace_prefix("Elixir.", "")

  def jsonable(%{__struct__: GenAgent.Backend.Error} = e), do: backend_error_message(e)

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

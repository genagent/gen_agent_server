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

  alias GenAgentServer.{PatternSpec, PublicSource, Run}

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
        "public_revision",
        "Resolve a public GitHub repository's default branch to its current commit SHA.",
        false,
        [req("repository", :string, "Public GitHub owner/repo")],
        fn a -> PublicSource.revision(a["repository"]) end
      ),
      op(
        "public_file",
        "Read a bounded UTF-8 source file from an exact public GitHub commit.",
        false,
        [
          req("repository", :string, "Public GitHub owner/repo"),
          req("sha", :string, "Full 40-character commit SHA"),
          req("path", :string, "Relative source file path (up to 128 KiB)")
        ],
        fn a -> PublicSource.file(a["repository"], a["sha"], a["path"]) end
      ),
      op(
        "public_issues",
        "Search up to 20 public GitHub issue titles and return their current states.",
        false,
        [
          req("repository", :string, "Public GitHub owner/repo"),
          req("query", :string, "Plain title search terms (up to 128 characters)"),
          opt("state", :string, "all, open, or closed (default: all)")
        ],
        fn a -> PublicSource.issues(a["repository"], a["query"], a["state"] || "all") end
      ),
      op(
        "public_issue",
        "Read a specific public GitHub issue for an exact duplicate check.",
        false,
        [
          req("repository", :string, "Public GitHub owner/repo"),
          req("number", :integer, "Issue number")
        ],
        fn a -> PublicSource.issue(a["repository"], a["number"]) end
      ),
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
        "discover_peers",
        "Discover existing Claude sessions and describe bindings. Read-only; peer support must be enabled.",
        false,
        [opt("name", :string, "Exact native session name (optional)")],
        fn a -> GenAgentServer.Peers.call(:discover, a) end
      ),
      op(
        "bind_peer",
        "Bind a claude:// alias to one verified existing native session. Never launches a replacement.",
        true,
        [
          req("address", :string, "Canonical provider-qualified alias"),
          req("session_id", :string, "Discovered native session ID")
        ],
        fn a -> GenAgentServer.Peers.call(:bind, a) end
      ),
      op(
        "send_peer_message",
        "Send bounded work to an existing peer. Socket write is not acknowledgement; duplicate keys never resend.",
        true,
        [
          req("address", :string, "Bound alias"),
          req("message", :string, "Task text (up to 65536 bytes)"),
          req("idempotency_key", :string, "Stable caller task key (up to 256 bytes)")
        ],
        fn a -> GenAgentServer.Peers.call(:send, a) end
      ),
      op(
        "peer_result",
        "Read the same correlated peer request repeatedly. Unknown execution or timeout never authorizes resending.",
        false,
        [req("id", :string, "Peer request ID")],
        fn a -> GenAgentServer.Peers.call(:result, a) end
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
          "enum" => ["read_only", "plan", "accept_edits"]
        },
        "codex_sandbox" => %{"type" => "string", "enum" => ["read_only", "workspace_write"]},
        "codex_user_config" => %{"type" => "string", "enum" => ["ignore", "inherit"]},
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

  defp guarded_jobs do
    GenAgentServer.Dispatch.jobs()
  catch
    :exit, {:noproc, _} -> []
  end

  # -- errors and encoding -----------------------------------------------------

  defp error(code, message), do: %{code: Atom.to_string(code), message: message}

  @doc false
  def normalize(reason) when is_atom(reason), do: error(reason, Atom.to_string(reason))

  def normalize({:invalid_config, detail}) when is_binary(detail),
    do: error(:invalid_config, detail)

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

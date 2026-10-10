defmodule GenAgentServer.InstanceSpec do
  @moduledoc """
  Parses a JSON-safe switchboard configuration into instance start options.

  This is the only path from client data to a runtime instance in
  `GenAgentServer.create_instance/2`. The configuration is data only:

      %{
        "cwd" => "/abs/project",
        "max_in_flight" => 4,
        "max_results" => 50,
        "routes" => [
          %{"name" => "plan", "provider" => "claude", "model" => "opus", "effort" => "high"},
          %{"name" => "review", "provider" => "codex", "codex_sandbox" => "read_only"},
          %{"name" => "smoke", "provider" => "echo"}
        ]
      }

  Every value is checked before anything starts. Unknown keys are rejected, so
  clients cannot supply modules, raw backend options, or pattern specs. Each
  route becomes a `GenAgentEnsemble.Agents.Simple` agent whose options come from
  `GenAgentServer.Providers.backend_opts/2`, so Claude uses a limited toolset
  and Codex a read-only sandbox unless the route opts in. Route descriptions
  include `review_read_only_explicit`, true only when a Claude/Codex route
  explicitly configured its read-only mode, false otherwise. This provenance
  field is not sent as a backend option. Atoms come from fixed
  lists, never from client strings.

  Route keys: `name`, `provider`, and, per provider, `model`, `effort`, `cwd`
  (absolute; defaults to the top-level `cwd`), `claude_permission_mode`
  (`read_only`, `plan`, `accept_edits`), `codex_sandbox` (`read_only`, `workspace_write`),
  `codex_user_config` (`ignore`, `inherit`), and `codex_response_text`
  (`all_messages`, `final_message`). `echo` takes no other keys.
  """

  alias GenAgentServer.Providers

  @top_keys ~w(cwd max_in_flight max_results routes)
  @provider_keys %{
    "echo" => [],
    "claude" => ~w(model effort cwd claude_permission_mode),
    "codex" => ~w(model effort cwd codex_sandbox codex_user_config codex_response_text)
  }
  @choices [
    claude_permission_mode: [:read_only, :plan, :accept_edits],
    codex_sandbox: [:read_only, :workspace_write],
    codex_user_config: [:ignore, :inherit],
    codex_response_text: [:all_messages, :final_message]
  ]

  @max_routes 16
  @max_in_flight 64
  @max_results 1000
  @default_in_flight 16
  @default_results 100

  @doc "Bounds applied to limits and route counts."
  def bounds,
    do: %{max_routes: @max_routes, max_in_flight: @max_in_flight, max_results: @max_results}

  @doc """
  Validate `config` for a new instance called `name`.

  Returns the arguments `GenAgentServer.start_instance/3` needs plus a sanitized
  description, or `{:error, reason}` where `reason` is `{:invalid_instance_name,
  name}` or `{:invalid_config, detail}`.
  """
  def parse(name, config) when is_binary(name) and is_map(config) do
    with :ok <- check_instance_name(name),
         :ok <- known_keys(config, @top_keys, "config"),
         {:ok, top_cwd} <- cwd(Map.get(config, "cwd"), "cwd"),
         {:ok, in_flight} <- limit(config, "max_in_flight", @default_in_flight, @max_in_flight),
         {:ok, results} <- limit(config, "max_results", @default_results, @max_results),
         {:ok, entries} <- entries(Map.get(config, "routes")),
         {:ok, routes} <- parse_routes(entries, top_cwd),
         :ok <- unique_names(routes),
         {:ok, agents} <- agents(routes) do
      {:ok,
       %{
         name: name,
         agents: agents,
         opts: [max_in_flight: in_flight, max_results: results],
         description: %{
           configured: true,
           routes: Enum.map(routes, & &1.description),
           limits: %{max_in_flight: in_flight, max_results: results}
         }
       }}
    end
  end

  # -- instance and routes -------------------------------------------------------

  defp check_instance_name(name) do
    if valid_name?(name), do: :ok, else: {:error, {:invalid_instance_name, name}}
  end

  defp valid_name?(name), do: Regex.match?(~r/\A[A-Za-z0-9][A-Za-z0-9._-]{0,63}\z/, name)

  defp entries(list) when is_list(list) and list != [] and length(list) <= @max_routes,
    do: {:ok, list}

  defp entries(_),
    do: invalid("routes must be a list of 1 to #{@max_routes} route objects")

  defp parse_routes(entries, top_cwd) do
    entries
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {entry, index}, {:ok, acc} ->
      case route(entry, "routes[#{index}]", top_cwd) do
        {:ok, route} -> {:cont, {:ok, [route | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, routes} -> {:ok, Enum.reverse(routes)}
      error -> error
    end
  end

  defp route(entry, path, top_cwd) when is_map(entry) do
    with {:ok, name} <- route_name(Map.get(entry, "name"), path),
         {:ok, provider} <- provider(Map.get(entry, "provider"), path),
         :ok <- provider_keys(entry, provider, path),
         {:ok, model} <- model(Map.get(entry, "model"), path),
         {:ok, effort} <- effort(provider, Map.get(entry, "effort"), path),
         {:ok, cwd} <- route_cwd(provider, Map.get(entry, "cwd"), top_cwd, path),
         {:ok, choices} <- route_choices(provider, entry, path) do
      description =
        %{name: name, provider: provider, model: model, effort: effort, cwd: cwd}
        |> Map.merge(Map.new(choices))
        |> Map.put(:review_read_only_explicit, explicit_review_read_only?(provider, entry))

      {:ok, %{name: name, provider: provider, description: description, opts: opts(description)}}
    end
  end

  defp route(_entry, path, _top_cwd), do: invalid("#{path} must be an object")

  # Preserve provider defaults while distinguishing explicit review access from omission.
  defp explicit_review_read_only?("codex", entry),
    do: entry["codex_sandbox"] == "read_only"

  defp explicit_review_read_only?("claude", entry),
    do: entry["claude_permission_mode"] == "read_only"

  defp explicit_review_read_only?(_, _), do: false

  defp route_name(name, path) when is_binary(name) do
    if valid_name?(name),
      do: {:ok, name},
      else:
        invalid(
          "#{path}.name must be 1 to 64 characters of letters, digits, . _ -, starting with a letter or digit"
        )
  end

  defp route_name(_name, path), do: invalid("#{path}.name is required")

  defp provider(provider, path) when is_binary(provider) do
    if Providers.known?(provider),
      do: {:ok, provider},
      else: invalid("#{path}.provider must be one of: #{Enum.join(Providers.names(), ", ")}")
  end

  defp provider(_provider, path), do: invalid("#{path}.provider is required")

  defp provider_keys(entry, provider, path) do
    allowed = ["name", "provider" | Map.fetch!(@provider_keys, provider)]

    case entry |> Map.keys() |> Enum.reject(&(&1 in allowed)) |> Enum.sort() do
      [] -> :ok
      extra -> invalid("#{path} has keys not supported for #{provider}: #{key_list(extra)}")
    end
  end

  defp model(nil, _path), do: {:ok, nil}

  defp model(model, path) do
    if is_binary(model) and Regex.match?(~r/\A[A-Za-z0-9][A-Za-z0-9._:\/@\[\]-]{0,127}\z/, model),
      do: {:ok, model},
      else: invalid("#{path}.model must be 1 to 128 model-name characters, not starting with -")
  end

  defp effort(_provider, nil, _path), do: {:ok, nil}

  defp effort(provider, value, path) do
    case Enum.find(
           Providers.efforts(provider),
           &(is_binary(value) and Atom.to_string(&1) == value)
         ) do
      nil ->
        invalid(
          "#{path}.effort must be one of: " <>
            Enum.join(Providers.efforts(provider), ", ")
        )

      atom ->
        {:ok, atom}
    end
  end

  defp route_cwd("echo", _cwd, _top_cwd, _path), do: {:ok, nil}

  defp route_cwd(_provider, nil, nil, path),
    do: invalid("#{path}.cwd or a top-level cwd is required for this provider")

  defp route_cwd(_provider, nil, top_cwd, _path), do: {:ok, top_cwd}
  defp route_cwd(_provider, cwd, _top_cwd, path), do: cwd(cwd, "#{path}.cwd")

  defp route_choices(provider, entry, path) do
    supported = Map.fetch!(@provider_keys, provider)

    @choices
    |> Enum.filter(fn {key, _allowed} -> Atom.to_string(key) in supported end)
    |> Enum.reduce_while({:ok, []}, fn {key, [default | _] = allowed}, {:ok, acc} ->
      name = Atom.to_string(key)

      case Map.get(entry, name) do
        nil ->
          {:cont, {:ok, [{key, default} | acc]}}

        value ->
          case Enum.find(allowed, &(is_binary(value) and Atom.to_string(&1) == value)) do
            nil -> {:halt, invalid("#{path}.#{name} must be one of: #{Enum.join(allowed, ", ")}")}
            atom -> {:cont, {:ok, [{key, atom} | acc]}}
          end
      end
    end)
  end

  defp opts(description) do
    description
    |> Map.take([
      :model,
      :effort,
      :cwd,
      :claude_permission_mode,
      :codex_sandbox,
      :codex_user_config,
      :codex_response_text
    ])
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp unique_names(routes) do
    names = Enum.map(routes, & &1.name)

    case Enum.uniq(names -- Enum.uniq(names)) do
      [] -> :ok
      dups -> invalid("duplicate route names: #{Enum.join(dups, ", ")}")
    end
  end

  defp agents(routes) do
    Enum.reduce_while(routes, {:ok, []}, fn route, {:ok, acc} ->
      case Providers.backend_opts(route.provider, route.opts) do
        {:ok, backend_opts} ->
          {:cont, {:ok, [{route.name, GenAgentEnsemble.Agents.Simple, backend_opts} | acc]}}

        {:error, {:not_a_directory, cwd}} ->
          {:halt, invalid("route #{route.name} cwd is not a directory: #{cwd}")}

        {:error, reason} ->
          {:halt, invalid("route #{route.name}: #{inspect(reason)}")}
      end
    end)
    |> case do
      {:ok, agents} -> {:ok, Enum.reverse(agents)}
      error -> error
    end
  end

  # -- scalars -------------------------------------------------------------------

  defp cwd(nil, _path), do: {:ok, nil}

  defp cwd(cwd, path) when is_binary(cwd) and byte_size(cwd) <= 4096 do
    cond do
      Path.type(cwd) != :absolute -> invalid("#{path} must be an absolute path")
      not File.dir?(cwd) -> invalid("#{path} is not an existing directory: #{cwd}")
      true -> {:ok, Path.expand(cwd)}
    end
  end

  defp cwd(_cwd, path), do: invalid("#{path} must be an absolute path string")

  defp limit(config, key, default, max) do
    case Map.get(config, key, default) do
      n when is_integer(n) and n >= 1 and n <= max -> {:ok, n}
      _ -> invalid("#{key} must be an integer from 1 to #{max}")
    end
  end

  defp known_keys(map, allowed, path) do
    case map |> Map.keys() |> Enum.reject(&(&1 in allowed)) |> Enum.sort() do
      [] -> :ok
      extra -> invalid("#{path} has unknown keys: #{key_list(extra)}")
    end
  end

  defp key_list(keys),
    do: Enum.map_join(keys, ", ", fn key -> if is_binary(key), do: key, else: inspect(key) end)

  defp invalid(detail), do: {:error, {:invalid_config, detail}}
end

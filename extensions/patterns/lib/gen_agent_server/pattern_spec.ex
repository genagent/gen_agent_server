defmodule GenAgentServer.PatternSpec do
  @moduledoc """
  Builds an Ensemble strategy and its options from a JSON-decoded spec.

  Specs contain only data, so they can come from a file, the CLI, or a remote
  caller. Options that Ensemble expects as functions are chosen by name from
  built-ins in this module.

  ## Agent entries

      %{"provider" => "claude", "name" => "reviewer", "role" => "You review Elixir.",
        "model" => "sonnet"}

  `provider` is required. `name` defaults per pattern. `role` is prepended to
  every prompt by `GenAgentServer.Agents.Role`.

  ## Patterns

    * `solo` -- `"agent"`.
    * `switchboard` -- `"agents"` (named; each name is a route).
    * `pipeline` -- `"stages"` (named, run in order).
    * `pool` -- `"worker"` and `"worker_count"`.
    * `supervisor` -- `"coordinator"`, `"worker"`, optional `"decomposer"`
      (`"numbered"` default, or `"lines"`) and `"max_subtasks"` (default 5).
    * `debate` -- `"agents"` (two), optional `"rounds"` (default 4; Ensemble
      counts total responses, not exchanges) and
      `"reply"` (`"transcript"` default, or `"last"`).
    * `consensus` -- `"agents"` (two or more), `"verdicts"` (for example
      `["approve", "revise", "reject"]`), optional `"threshold"`
      (`"majority"` default, `"unanimous"`, or an integer) and `"rounds"`
      (default 3). Each agent must end its answer with a line
      `VERDICT: <word>`; the role preamble says so automatically.
  """

  alias GenAgentServer.{Agents, Providers}

  @patterns %{
    "solo" => GenAgentEnsemble.Strategies.Solo,
    "switchboard" => GenAgentEnsemble.Strategies.Switchboard,
    "pipeline" => GenAgentEnsemble.Strategies.Pipeline,
    "pool" => GenAgentEnsemble.Strategies.Pool,
    "supervisor" => GenAgentEnsemble.Strategies.Supervisor,
    "debate" => GenAgentEnsemble.Strategies.Debate,
    "consensus" => GenAgentEnsemble.Strategies.Consensus
  }

  @type plan :: %{
          pattern: String.t(),
          strategy: module(),
          strategy_opts: keyword(),
          routes: [String.t()]
        }

  def patterns, do: @patterns |> Map.keys() |> Enum.sort()

  @doc """
  Parse `spec`. `opts` supplies defaults for agent entries: `:cwd`,
  `:codex_sandbox`, `:codex_user_config`, `:codex_response_text`,
  `:claude_permission_mode`. The spec keys `"cwd"`,
  `"codex_sandbox"` (`"read_only"` or `"workspace_write"`),
  `"codex_user_config"` (`"ignore"` or `"inherit"`),
  `"codex_response_text"` (`"all_messages"` or `"final_message"`), and
  `"claude_permission_mode"` (`"plan"` or `"accept_edits"`) override them.
  Both CLI providers are read-only unless a spec opts in.
  """
  @spec parse(map(), keyword()) :: {:ok, plan()} | {:error, term()}
  def parse(spec, opts \\ [])

  def parse(%{"pattern" => pattern} = spec, opts) when is_map_key(@patterns, pattern) do
    opts =
      case spec do
        %{"cwd" => cwd} when is_binary(cwd) -> Keyword.put(opts, :cwd, Path.expand(cwd))
        _ -> opts
      end

    with {:ok, opts} <- provider_options(spec, opts),
         {:ok, strategy_opts, routes} <- build(pattern, spec, opts) do
      {:ok,
       %{
         pattern: pattern,
         strategy: Map.fetch!(@patterns, pattern),
         strategy_opts: strategy_opts,
         routes: routes
       }}
    end
  end

  def parse(%{"pattern" => pattern}, _opts), do: {:error, {:unknown_pattern, pattern}}
  def parse(_spec, _opts), do: {:error, :pattern_required}

  defp build("solo", spec, opts) do
    with {:ok, agent} <- agent(spec["agent"], "agent", opts), do: {:ok, [agent: agent], ["run"]}
  end

  defp build("switchboard", spec, opts) do
    with {:ok, agents} <- named_agents(spec["agents"], "agent", 1, opts) do
      {:ok, [agents: agents], Enum.map(agents, &elem(&1, 0))}
    end
  end

  defp build("pipeline", spec, opts) do
    with {:ok, stages} <- named_agents(spec["stages"], "stage", 1, opts),
         do: {:ok, [stages: stages], ["run"]}
  end

  defp build("pool", spec, opts) do
    with {:ok, count} <- pos_int(spec, "worker_count", nil),
         {:ok, worker} <- agent(spec["worker"], "worker", opts) do
      {:ok, [worker_count: count, worker_template: worker], ["run"]}
    end
  end

  defp build("supervisor", spec, opts) do
    with {:ok, coordinator} <- agent(spec["coordinator"], "coordinator", opts),
         {:ok, worker} <- agent(spec["worker"], "worker", opts),
         {:ok, max} <- pos_int(spec, "max_subtasks", 5),
         {:ok, decomposer} <- decomposer(Map.get(spec, "decomposer", "numbered"), max) do
      {:ok, [coordinator: coordinator, worker_template: worker, decomposer: decomposer], ["run"]}
    end
  end

  defp build("debate", spec, opts) do
    with {:ok, agents} <- named_agents(spec["agents"], "debater", 2, opts),
         :ok <- exactly(agents, 2),
         {:ok, rounds} <- pos_int(spec, "rounds", 4),
         {:ok, reply} <-
           one_of(spec, "reply", %{"transcript" => :transcript, "last" => :last}, "transcript") do
      {:ok, [agents: agents, rounds: rounds, reply: reply], ["run"]}
    end
  end

  defp build("consensus", spec, opts) do
    with {:ok, verdicts} <- verdicts(spec["verdicts"]),
         role_suffix = verdict_instruction(Map.keys(verdicts)),
         {:ok, agents} <- named_agents(spec["agents"], "member", 2, opts, role_suffix),
         {:ok, rounds} <- pos_int(spec, "rounds", 3),
         {:ok, threshold} <- threshold(Map.get(spec, "threshold", "majority"), length(agents)) do
      {:ok,
       [
         agents: agents,
         verdict_parser: &parse_verdict(&1, verdicts),
         threshold: threshold,
         rounds: rounds
       ], ["run"]}
    end
  end

  # Provider options are limited to the choices profiles allow.
  defp provider_options(spec, opts) do
    with {:ok, opts} <-
           edit_mode(spec, opts, "codex_sandbox", %{
             "read_only" => :read_only,
             "workspace_write" => :workspace_write
           }),
         {:ok, opts} <-
           edit_mode(spec, opts, "codex_user_config", %{
             "ignore" => :ignore,
             "inherit" => :inherit
           }),
         {:ok, opts} <-
           edit_mode(spec, opts, "codex_response_text", %{
             "all_messages" => :all_messages,
             "final_message" => :final_message
           }) do
      edit_mode(spec, opts, "claude_permission_mode", %{
        "plan" => :plan,
        "accept_edits" => :accept_edits
      })
    end
  end

  defp edit_mode(spec, opts, key, choices) do
    case Map.fetch(spec, key) do
      :error ->
        {:ok, opts}

      {:ok, value} ->
        case Map.fetch(choices, value) do
          {:ok, atom} -> {:ok, Keyword.put(opts, String.to_existing_atom(key), atom)}
          :error -> {:error, {:invalid, key, value}}
        end
    end
  end

  # -- agents ----------------------------------------------------------------

  defp named_agents(entries, prefix, min, opts, role_suffix \\ nil)

  defp named_agents(entries, prefix, min, opts, role_suffix)
       when is_list(entries) and length(entries) >= min do
    entries
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {entry, i}, {:ok, acc} ->
      case agent(entry, "#{prefix}-#{i}", opts, role_suffix) do
        {:ok, spec} -> {:cont, {:ok, [spec | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, specs} ->
        specs = Enum.reverse(specs)
        names = Enum.map(specs, &elem(&1, 0))

        if length(names) == length(Enum.uniq(names)),
          do: {:ok, specs},
          else: {:error, :duplicate_agent_names}

      error ->
        error
    end
  end

  defp named_agents(_entries, prefix, min, _opts, _suffix),
    do: {:error, {:needs_agents, prefix, min}}

  defp agent(entry, default_name, opts, role_suffix \\ nil)

  defp agent(%{"provider" => provider} = entry, default_name, opts, role_suffix) do
    name = Map.get(entry, "name", default_name)
    role = Map.get(entry, "role")

    provider_opts =
      opts
      |> Keyword.take([
        :cwd,
        :codex_sandbox,
        :codex_user_config,
        :codex_response_text,
        :claude_permission_mode
      ])
      |> put_model(entry)

    cond do
      not (is_binary(name) and name != "" and not String.contains?(name, "/")) ->
        {:error, {:invalid_agent_name, name}}

      not (is_nil(role) or is_binary(role)) ->
        {:error, {:invalid_role, name}}

      true ->
        with {:ok, backend_opts} <- Providers.backend_opts(provider, provider_opts) do
          role = join_role(role, role_suffix)
          backend_opts = if role, do: backend_opts ++ [role: role], else: backend_opts
          {:ok, {name, Agents.Role, backend_opts}}
        end
    end
  end

  defp agent(nil, default_name, _opts, _suffix), do: {:error, {:agent_required, default_name}}

  defp agent(_entry, default_name, _opts, _suffix),
    do: {:error, {:provider_required, default_name}}

  defp put_model(opts, %{"model" => model}) when is_binary(model),
    do: Keyword.put(opts, :model, model)

  defp put_model(opts, _entry), do: opts

  defp join_role(nil, nil), do: nil
  defp join_role(role, nil), do: role
  defp join_role(nil, suffix), do: suffix
  defp join_role(role, suffix), do: role <> "\n\n" <> suffix

  # -- scalars -----------------------------------------------------------------

  defp pos_int(spec, key, default) do
    case Map.get(spec, key, default) do
      n when is_integer(n) and n > 0 -> {:ok, n}
      nil -> {:error, {:required, key}}
      other -> {:error, {:invalid, key, other}}
    end
  end

  defp one_of(spec, key, choices, default) do
    value = Map.get(spec, key, default)

    case Map.fetch(choices, value) do
      {:ok, atom} -> {:ok, atom}
      :error -> {:error, {:invalid, key, value}}
    end
  end

  defp exactly(list, n) when length(list) == n, do: :ok
  defp exactly(list, n), do: {:error, {:expected_agents, n, length(list)}}

  # -- built-in functions ------------------------------------------------------

  @doc false
  def decomposer("lines", max), do: {:ok, &(&1 |> split_lines() |> Enum.take(max))}

  def decomposer("numbered", max) do
    {:ok,
     fn text ->
       text
       |> String.split("\n")
       |> Enum.flat_map(fn line ->
         case Regex.run(~r/(?:^|\s)(?:\d+[.)]|[-*])\s+(.+)$/u, line) do
           [_, item] -> [String.trim(item)]
           nil -> []
         end
       end)
       |> Enum.reject(&(&1 == ""))
       |> Enum.take(max)
     end}
  end

  def decomposer(other, _max), do: {:error, {:invalid, "decomposer", other}}

  defp split_lines(text) do
    text |> String.split("\n") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end

  defp verdicts(list) when is_list(list) and list != [] do
    words = Enum.map(list, &(is_binary(&1) && String.downcase(String.trim(&1))))

    if Enum.all?(words, &(is_binary(&1) and Regex.match?(~r/^[a-z][a-z_]*$/, &1))) do
      # Atoms are created only from the operator's spec, never from model output.
      {:ok, Map.new(words, &{&1, String.to_atom(&1)})}
    else
      {:error, {:invalid, "verdicts", list}}
    end
  end

  defp verdicts(other), do: {:error, {:invalid, "verdicts", other}}

  defp verdict_instruction(words) do
    "End your answer with a final line of the form `VERDICT: <word>`, where <word> is one of: " <>
      Enum.join(Enum.sort(words), ", ") <> "."
  end

  @doc false
  def parse_verdict(text, verdicts) do
    lines = String.split(text, "\n")

    lines
    |> Enum.with_index()
    |> Enum.reverse()
    |> Enum.find_value(:error, fn {line, i} ->
      with [_, word] <- Regex.run(~r/VERDICT:\s*\**\s*([A-Za-z_]+)/u, line),
           {:ok, atom} <- Map.fetch(verdicts, String.downcase(word)) do
        rationale = lines |> List.delete_at(i) |> Enum.join("\n") |> String.trim()
        {:ok, atom, rationale}
      else
        _ -> nil
      end
    end)
  end

  defp threshold("majority", _n), do: {:ok, :majority}
  defp threshold("unanimous", _n), do: {:ok, :unanimous}
  defp threshold(k, n) when is_integer(k) and k > 0 and k <= n, do: {:ok, {:at_least, k}}
  defp threshold(other, _n), do: {:error, {:invalid, "threshold", other}}
end

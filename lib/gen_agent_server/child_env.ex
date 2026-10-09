defmodule GenAgentServer.ChildEnv do
  @moduledoc """
  Child-process environment for the Claude and Codex CLI backends.

  When this server runs from an Elixir release, the VM inherits release boot
  variables (`RELEASE_*`, including the node cookie, plus `BINDIR` and
  `ROOTDIR`) and a `PATH` that starts with the release `bin` and bundled
  `erts-*/bin` directories. Provider CLIs and their subprocesses (for example
  a project's own `mix`) inherit those and misbehave: `mix` looks for the
  release's `start.boot` instead of its own.

  `normalize/2` builds the `:env` entries a backend passes to its runner so
  the child does not see those values. It never mutates the server's own
  environment and does not copy unrelated inherited values into child options
  or log them, so
  provider credentials and other inherited settings reach the child untouched.
  Shared MCP configuration (`GEN_AGENT_SERVER_SHARED_MCP_*`), including the
  bearer token, is always unset in provider children, even in trusted overrides.

  ## Rules, in order

    1. Trusted overrides (`:env` under `:provider_overrides`, a map or
       `{name, value}` list; names strings or atoms; values strings or `false`
       to unset) are taken first. `false` is passed through as a Port unset.
    2. Release boot variables and every `GEN_AGENT_SERVER_SHARED_MCP_*`
       variable are then forced to `false` in children, including trusted
       overrides. `BINDIR` and `ROOTDIR` are also unset.
    3. `PATH` cleanup runs last, over the override `PATH` when one is given
       and over the inherited `PATH` otherwise. Only entries equal to the
       release runtime directories are removed: `BINDIR`, `ROOTDIR/bin`,
       `RELEASE_ROOT/bin`, and `ROOTDIR|RELEASE_ROOT/erts-<v>/bin`. Entries are
       compared whole, so `/opt/app/bin-tools` or `/opt/app/bin/extra` stay.
       `PATH` is only emitted when it was overridden or actually changed.

  Entries are returned sorted by name as `{String.t(), String.t() | false}`
  tuples, which both backend streaming Port launch paths accept.
  """

  @boot_names ["BINDIR", "ROOTDIR"]
  @cli_backends [GenAgent.Backends.Claude, GenAgent.Backends.Codex]

  @type env_input :: map() | [{String.t() | atom(), String.t() | false}]
  @type entry :: {String.t(), String.t() | false}

  @doc """
  Environment entries for a provider child.

  `overrides` is the trusted env override (see the module rules). `parent`
  defaults to this VM's environment and exists so tests can supply a fake one.
  """
  @spec normalize(env_input(), map()) :: [entry()]
  def normalize(overrides \\ [], parent \\ System.get_env()) when is_map(parent) do
    overrides = normalize_overrides(overrides)

    overrides
    |> unset_boot_vars(parent)
    |> clean_path(overrides, parent)
    |> Enum.sort_by(&elem(&1, 0))
  end

  @doc """
  Puts normalized `:env` on CLI backend options; other backends are returned
  unchanged. Any existing `:env` is treated as the trusted override, so the
  result is stable when applied more than once.
  """
  @spec harden_backend_opts(keyword()) :: keyword()
  def harden_backend_opts(backend_opts) when is_list(backend_opts) do
    if Keyword.get(backend_opts, :backend) in @cli_backends do
      Keyword.put(backend_opts, :env, normalize(Keyword.get(backend_opts, :env) || []))
    else
      backend_opts
    end
  end

  @doc """
  Applies `harden_backend_opts/1` to `{name, agent_module, backend_opts}`
  tuples. Other shapes pass through for custom strategies.
  """
  @spec harden_agents(list()) :: list()
  def harden_agents(agents) when is_list(agents) do
    Enum.map(agents, fn
      {name, agent, backend_opts} when is_list(backend_opts) ->
        {name, agent, harden_backend_opts(backend_opts)}

      other ->
        other
    end)
  end

  @doc "True for a variable name this module always unsets in children."
  @spec boot_var?(String.t()) :: boolean()
  def boot_var?(name) when is_binary(name) do
    name in @boot_names or String.starts_with?(name, "RELEASE_") or
      String.starts_with?(name, "GEN_AGENT_SERVER_SHARED_MCP_")
  end

  defp normalize_overrides(nil), do: %{}

  defp normalize_overrides(overrides) when is_map(overrides) or is_list(overrides) do
    Map.new(overrides, fn
      {key, value}
      when (is_binary(key) or is_atom(key)) and (is_binary(value) or value == false) ->
        {to_string(key), value}

      _entry ->
        raise ArgumentError, "provider override env entries must be {name, string | false}"
    end)
  end

  defp unset_boot_vars(env, parent) do
    names =
      (Map.keys(parent) ++ Map.keys(env))
      |> Enum.filter(&boot_var?/1)
      |> MapSet.new()
      |> MapSet.union(MapSet.new(@boot_names))

    Enum.reduce(names, env, fn name, acc -> Map.put(acc, name, false) end)
  end

  defp clean_path(env, overrides, parent) do
    {source, explicit?} =
      case Map.get(overrides, "PATH") do
        false -> {false, true}
        path when is_binary(path) -> {path, true}
        nil -> {Map.get(parent, "PATH"), false}
      end

    case source do
      path when is_binary(path) ->
        cleaned = strip_release_entries(path, parent)

        if explicit? or cleaned != path do
          Map.put(env, "PATH", cleaned)
        else
          env
        end

      _ ->
        env
    end
  end

  defp strip_release_entries(path, parent) do
    release_dirs = release_dirs(parent)
    erts_roots = erts_roots(parent)

    path
    |> String.split(":")
    |> Enum.reject(fn entry ->
      normalized = trim_trailing_slash(entry)

      normalized in release_dirs or
        Enum.any?(erts_roots, fn root -> erts_bin?(normalized, root) end)
    end)
    |> Enum.join(":")
  end

  defp release_dirs(parent) do
    roots = roots(parent)

    bins =
      case Map.get(parent, "BINDIR") do
        bindir when is_binary(bindir) and bindir != "" -> [trim_trailing_slash(bindir)]
        _ -> []
      end

    MapSet.new(bins ++ Enum.map(roots, &(&1 <> "/bin")))
  end

  defp erts_roots(parent), do: roots(parent)

  defp roots(parent) do
    ["ROOTDIR", "RELEASE_ROOT"]
    |> Enum.map(&Map.get(parent, &1))
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.map(&trim_trailing_slash/1)
    |> Enum.uniq()
  end

  # `<root>/erts-<version>/bin` exactly, nothing deeper or beside it.
  defp erts_bin?(entry, root) do
    prefix = root <> "/erts-"

    String.starts_with?(entry, prefix) and
      case String.split(String.replace_prefix(entry, prefix, ""), "/") do
        [version, "bin"] when version != "" -> true
        _ -> false
      end
  end

  defp trim_trailing_slash("/"), do: "/"
  defp trim_trailing_slash(entry), do: String.trim_trailing(entry, "/")
end

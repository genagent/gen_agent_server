defmodule GenAgentServer.Profiles do
  @moduledoc """
  Reads named, read-only project profiles for a running server.

  Profile names are instance names. Each profile has its own backend sessions
  and invocation results, even when two profiles use the same provider.
  """

  @backends %{
    "echo" => GenAgentEnsemble.Backends.Echo,
    "claude" => GenAgent.Backends.Claude,
    "codex" => GenAgent.Backends.Codex
  }

  def load!(path) when is_binary(path) do
    path = Path.expand(path)
    document = path |> File.read!() |> Jason.decode!()

    profiles =
      case document do
        %{"profiles" => entries} when is_list(entries) -> entries
        %{} = object when not is_map_key(object, "profiles") -> []
        _ -> raise ArgumentError, "#{path} must contain a profiles array"
      end

    result = Enum.map(profiles, &parse_profile!(&1, Path.dirname(path)))
    names = Enum.map(result, &elem(&1, 0))

    if length(names) != length(Enum.uniq(names)) do
      raise ArgumentError, "#{path} contains duplicate profile names"
    end

    result
  end

  defp parse_profile!(%{"name" => name, "cwd" => cwd, "providers" => providers}, base)
       when is_binary(name) and is_binary(cwd) and is_list(providers) do
    unless name != "" and not String.contains?(name, "/") do
      raise ArgumentError, "profile name must be non-empty and contain no slash"
    end

    cwd = Path.expand(cwd, base)

    unless File.dir?(cwd) do
      raise ArgumentError, "profile #{name} cwd is not a directory: #{cwd}"
    end

    unless providers != [] and Enum.all?(providers, &Map.has_key?(@backends, &1)) do
      raise ArgumentError, "profile #{name} must list known providers: echo, claude, codex"
    end

    if length(providers) != length(Enum.uniq(providers)) do
      raise ArgumentError, "profile #{name} contains duplicate providers"
    end

    agents =
      Enum.map(providers, fn provider ->
        opts =
          case provider do
            "echo" ->
              [backend: @backends[provider]]

            "claude" ->
              [backend: @backends[provider], cwd: cwd, permission_mode: :plan]

            "codex" ->
              [
                backend: @backends[provider],
                cwd: cwd,
                sandbox: :read_only,
                approval_policy: :never
              ]
          end

        {provider, GenAgentEnsemble.Agents.Simple, opts}
      end)

    {name, agents}
  end

  defp parse_profile!(_entry, _base) do
    raise ArgumentError, "each profile needs a name, cwd, and providers array"
  end
end

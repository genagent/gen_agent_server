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

  defp parse_profile!(%{"name" => name, "cwd" => cwd, "providers" => providers} = entry, base)
       when is_binary(name) and is_binary(cwd) and is_list(providers) do
    unless name != "" and not String.contains?(name, "/") and
             not String.match?(name, ~r/[\x00-\x1F\x7F]/u) do
      raise ArgumentError,
            "profile name must be non-empty and contain no slash or control characters"
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

    allowed_keys = ~w(name cwd providers codex_sandbox claude_permission_mode)

    unless Enum.all?(Map.keys(entry), &(&1 in allowed_keys)) do
      raise ArgumentError, "profile #{name} contains unknown fields"
    end

    codex_sandbox = Map.get(entry, "codex_sandbox", "read_only")
    claude_permission = Map.get(entry, "claude_permission_mode", "plan")

    unless codex_sandbox in ["read_only", "workspace_write"] do
      raise ArgumentError, "profile #{name} has invalid codex_sandbox"
    end

    unless claude_permission in ["plan", "accept_edits"] do
      raise ArgumentError, "profile #{name} has invalid claude_permission_mode"
    end

    if Map.has_key?(entry, "codex_sandbox") and "codex" not in providers do
      raise ArgumentError, "profile #{name} sets codex_sandbox without codex"
    end

    if Map.has_key?(entry, "claude_permission_mode") and "claude" not in providers do
      raise ArgumentError, "profile #{name} sets claude_permission_mode without claude"
    end

    codex_sandbox = if codex_sandbox == "read_only", do: :read_only, else: :workspace_write
    claude_permission = if claude_permission == "plan", do: :plan, else: :accept_edits

    agents =
      Enum.map(providers, fn provider ->
        opts =
          case provider do
            "echo" ->
              [backend: @backends[provider]]

            "claude" ->
              [backend: @backends[provider], cwd: cwd, permission_mode: claude_permission]

            "codex" ->
              [
                backend: @backends[provider],
                cwd: cwd,
                sandbox: codex_sandbox,
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

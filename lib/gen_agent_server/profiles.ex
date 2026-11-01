defmodule GenAgentServer.Profiles do
  @moduledoc """
  Reads named project profiles with inherited CLI access by default for a running server.

  Profile names are instance names. Each profile has its own backend sessions
  and invocation results, even when two profiles use the same provider.
  """

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

    unless providers != [] and Enum.all?(providers, &GenAgentServer.Providers.known?/1) do
      raise ArgumentError, "profile #{name} must list known providers: echo, claude, codex"
    end

    if length(providers) != length(Enum.uniq(providers)) do
      raise ArgumentError, "profile #{name} contains duplicate providers"
    end

    allowed_keys =
      ~w(name cwd providers codex_sandbox codex_user_config codex_response_text claude_permission_mode)

    unless Enum.all?(Map.keys(entry), &(&1 in allowed_keys)) do
      raise ArgumentError, "profile #{name} contains unknown fields"
    end

    codex_sandbox = access_choice!(entry, :codex_sandbox, name)
    codex_user_config = access_choice!(entry, :codex_user_config, name)
    claude_permission = access_choice!(entry, :claude_permission_mode, name)
    codex_response_text = Map.get(entry, "codex_response_text", "all_messages")

    unless codex_response_text in ["all_messages", "final_message"] do
      raise ArgumentError, "profile #{name} has invalid codex_response_text"
    end

    if Map.has_key?(entry, "codex_sandbox") and "codex" not in providers do
      raise ArgumentError, "profile #{name} sets codex_sandbox without codex"
    end

    if Map.has_key?(entry, "codex_user_config") and "codex" not in providers do
      raise ArgumentError, "profile #{name} sets codex_user_config without codex"
    end

    if Map.has_key?(entry, "codex_response_text") and "codex" not in providers do
      raise ArgumentError, "profile #{name} sets codex_response_text without codex"
    end

    if Map.has_key?(entry, "claude_permission_mode") and "claude" not in providers do
      raise ArgumentError, "profile #{name} sets claude_permission_mode without claude"
    end

    provider_opts = [
      cwd: cwd,
      codex_sandbox: codex_sandbox,
      codex_user_config: codex_user_config,
      codex_response_text: String.to_existing_atom(codex_response_text),
      claude_permission_mode: claude_permission
    ]

    agents =
      Enum.map(providers, fn provider ->
        {:ok, opts} = GenAgentServer.Providers.backend_opts(provider, provider_opts)
        {provider, GenAgentEnsemble.Agents.Simple, opts}
      end)

    {name, agents}
  end

  defp parse_profile!(_entry, _base) do
    raise ArgumentError, "each profile needs a name, cwd, and providers array"
  end

  defp access_choice!(entry, key, name) do
    allowed = GenAgentServer.Providers.access_choices(key)
    value = Map.get(entry, Atom.to_string(key), Atom.to_string(hd(allowed)))

    Enum.find(allowed, &(Atom.to_string(&1) == value)) ||
      raise ArgumentError, "profile #{name} has invalid #{key}"
  end
end

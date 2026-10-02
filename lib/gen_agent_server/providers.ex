defmodule GenAgentServer.Providers do
  @moduledoc """
  The provider names this server accepts and the backend options it uses for
  each.

  Static profiles default Claude to plan permission mode. Dynamic MCP routes
  default to `:read_only`, which uses `dontAsk` with only Read, Grep, and Glob
  tools. Codex defaults to a read-only sandbox with approvals disabled and the
  host user's config ignored. Callers can opt in to edit modes or config
  inheritance.
  """

  @claude_efforts [:low, :medium, :high, :xhigh, :max]
  @codex_efforts [:low, :medium, :high]

  @backends %{
    "echo" => GenAgentEnsemble.Backends.Echo,
    "claude" => GenAgent.Backends.Claude,
    "codex" => GenAgent.Backends.Codex
  }

  @doc "Provider names, sorted."
  def names, do: @backends |> Map.keys() |> Enum.sort()

  def known?(provider), do: Map.has_key?(@backends, provider)

  @doc """
  Backend options for `provider`.

  Options:

    * `:cwd` -- project directory for the CLI backends (required for `claude`
      and `codex`).
    * `:codex_sandbox` -- `:read_only` (default) or `:workspace_write`.
    * `:codex_user_config` -- `:ignore` (default) or `:inherit`.
    * `:claude_permission_mode` -- `:plan` (default for profiles),
      `:read_only` (default for dynamic routes), or `:accept_edits`.
    * `:model` -- model name passed to the CLI backends.
    * `:effort` -- reasoning effort, one of `efforts/1` for the provider.
      Claude takes it as its `:effort` option. Codex gets the fixed
      `model_reasoning_effort` config override, which the adapter sends on
      fresh and resumed turns.

  Operators and tests can set `:provider_overrides` in the `:gen_agent_server`
  application environment to a map of provider name to keyword options merged
  over the result (for example a replacement `:backend`). It is trusted
  configuration; no operation accepts it from a client.
  """
  def backend_opts(provider, opts \\ []) do
    with {:ok, base} <- build_opts(provider, opts) do
      overrides = Application.get_env(:gen_agent_server, :provider_overrides, %{})
      {:ok, Keyword.merge(base, Map.get(overrides, provider, []))}
    end
  end

  @doc "Effort values `backend_opts/2` accepts for `provider`."
  def efforts("claude"), do: @claude_efforts
  def efforts("codex"), do: @codex_efforts
  def efforts(_provider), do: []

  defp build_opts("echo", _opts), do: {:ok, [backend: @backends["echo"]]}

  defp build_opts("claude", opts) do
    with {:ok, cwd} <- fetch_cwd(opts),
         {:ok, mode} <- choice(opts, :claude_permission_mode, [:plan, :read_only, :accept_edits]),
         {:ok, effort} <- effort(opts, @claude_efforts) do
      base = [backend: @backends["claude"], cwd: cwd] ++ claude_access_opts(mode)
      base = if effort, do: base ++ [effort: effort], else: base
      {:ok, maybe_model(base, opts)}
    end
  end

  defp build_opts("codex", opts) do
    with {:ok, cwd} <- fetch_cwd(opts),
         {:ok, sandbox} <- choice(opts, :codex_sandbox, [:read_only, :workspace_write]),
         {:ok, user_config} <- choice(opts, :codex_user_config, [:ignore, :inherit]),
         {:ok, effort} <- effort(opts, @codex_efforts) do
      base = [backend: @backends["codex"], cwd: cwd, sandbox: sandbox, approval_policy: :never]
      base = if user_config == :ignore, do: base ++ [ignore_user_config: true], else: base

      base =
        if effort,
          do: base ++ [config_overrides: [~s(model_reasoning_effort="#{effort}")]],
          else: base

      {:ok, maybe_model(base, opts)}
    end
  end

  defp build_opts(provider, _opts), do: {:error, {:unknown_provider, provider}}

  defp claude_access_opts(:read_only),
    do: [permission_mode: :dont_ask, tools: ["Read", "Grep", "Glob"]]

  defp claude_access_opts(mode), do: [permission_mode: mode]

  defp effort(opts, allowed) do
    case Keyword.get(opts, :effort) do
      nil ->
        {:ok, nil}

      value ->
        if value in allowed, do: {:ok, value}, else: {:error, {:invalid_option, :effort, value}}
    end
  end

  defp fetch_cwd(opts) do
    case Keyword.get(opts, :cwd) do
      cwd when is_binary(cwd) ->
        if File.dir?(cwd), do: {:ok, cwd}, else: {:error, {:not_a_directory, cwd}}

      _ ->
        {:error, :cwd_required}
    end
  end

  defp choice(opts, key, [default | _] = allowed) do
    value = Keyword.get(opts, key, default)
    if value in allowed, do: {:ok, value}, else: {:error, {:invalid_option, key, value}}
  end

  defp maybe_model(backend_opts, opts) do
    case Keyword.get(opts, :model) do
      model when is_binary(model) and model != "" -> backend_opts ++ [model: model]
      _ -> backend_opts
    end
  end
end

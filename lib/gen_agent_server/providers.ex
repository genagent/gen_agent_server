defmodule GenAgentServer.Providers do
  @moduledoc """
  The provider names this server accepts and the backend options it uses for
  each.

  Access defaults to `:inherit`: no server tools, permission mode, sandbox, or
  user-config overrides are supplied. CLI settings belong to the server process
  user; transient client permissions are not transferred. Headless sessions
  cannot answer prompts. Codex retains disabled approvals. Effective access
  depends on CLI configuration and host permissions. Codex response text defaults
  to all completed agent messages.
  """

  @claude_efforts [:low, :medium, :high, :xhigh, :max]
  @codex_efforts [:low, :medium, :high]

  @backends %{
    "echo" => GenAgentEnsemble.Backends.Echo,
    "claude" => GenAgent.Backends.Claude,
    "codex" => GenAgent.Backends.Codex
  }

  @doc "Fixed access choices, with the default first."
  def access_choices(:claude_permission_mode),
    do: [:inherit, :read_only, :plan, :accept_edits, :auto, :bypass_permissions, :dont_ask]

  def access_choices(:codex_sandbox), do: [:inherit, :read_only, :workspace_write]
  def access_choices(:codex_user_config), do: [:inherit, :ignore]

  # Runtime configuration must not capture application overrides or child env
  # while config/runtime.exs is still being evaluated. Instance start hardens it.
  @doc false
  def startup_backend_opts(provider, opts), do: build_opts(provider, opts)

  @doc "Provider names, sorted."
  def names, do: @backends |> Map.keys() |> Enum.sort()

  def known?(provider), do: Map.has_key?(@backends, provider)

  @doc """
  Backend options for `provider`.

  Options:

    * `:cwd` -- project directory for the CLI backends (required for `claude`
      and `codex`).
    * `:codex_sandbox` -- `:inherit` (default), `:read_only`, or `:workspace_write`.
    * `:codex_user_config` -- `:inherit` (default) or `:ignore`.
    * `:codex_response_text` -- `:all_messages` (default) or `:final_message`.
    * `:claude_permission_mode` -- `:inherit` (default), `:read_only`, `:plan`,
      `:accept_edits`, `:auto`, `:bypass_permissions`, or `:dont_ask`.
    * `:model` -- model name passed to the CLI backends.
    * `:effort` -- reasoning effort, one of `efforts/1` for the provider.
      Claude takes it as its `:effort` option. Codex gets the fixed
      `model_reasoning_effort` config override, which the adapter sends on
      fresh and resumed turns.

  Operators and tests can set `:provider_overrides` in the `:gen_agent_server`
  application environment to a map of provider name to keyword options merged
  over the result (for example a replacement `:backend`). It is trusted
  configuration; no operation accepts it from a client, and no client-facing
  schema exposes `:env`.

  ## Child environment

  For the Claude and Codex CLI backends the result always carries an `:env`
  built by `GenAgentServer.ChildEnv.normalize/2`. Priority, lowest to highest:

    1. server defaults built here;
    2. `:provider_overrides` keyword options, merged over the defaults. Its
       `:env` (map or `{name, value}` list, values strings or `false` to
       unset) is the trusted environment override;
    3. release-boot cleanup applied last: `RELEASE_*`, `BINDIR`, and `ROOTDIR`
       are unset in the child even if an override names them, and release
       `bin`/`erts-*/bin` entries are removed from the override or inherited
       `PATH`.

  Everything else in the server's environment (credentials included) reaches
  the child unchanged; inherited values are not copied into options or logged.
  Overrides that swap in a non-CLI `:backend` pass through unchanged.
  """
  def backend_opts(provider, opts \\ []) do
    with {:ok, base} <- build_opts(provider, opts) do
      overrides = Application.get_env(:gen_agent_server, :provider_overrides, %{})

      {:ok,
       base
       |> Keyword.merge(Map.get(overrides, provider, []))
       |> GenAgentServer.ChildEnv.harden_backend_opts()}
    end
  end

  @doc "Effort values `backend_opts/2` accepts for `provider`."
  def efforts("claude"), do: @claude_efforts
  def efforts("codex"), do: @codex_efforts
  def efforts(_provider), do: []

  defp build_opts("echo", _opts), do: {:ok, [backend: @backends["echo"]]}

  defp build_opts("claude", opts) do
    with {:ok, cwd} <- fetch_cwd(opts),
         {:ok, mode} <-
           choice(opts, :claude_permission_mode, access_choices(:claude_permission_mode)),
         {:ok, effort} <- effort(opts, @claude_efforts) do
      base = [backend: @backends["claude"], working_dir: cwd] ++ claude_access_opts(mode)
      base = if effort, do: base ++ [effort: effort], else: base
      {:ok, maybe_model(base, opts)}
    end
  end

  defp build_opts("codex", opts) do
    with {:ok, cwd} <- fetch_cwd(opts),
         {:ok, sandbox} <- choice(opts, :codex_sandbox, access_choices(:codex_sandbox)),
         {:ok, user_config} <-
           choice(opts, :codex_user_config, access_choices(:codex_user_config)),
         {:ok, response_text} <-
           choice(opts, :codex_response_text, [:all_messages, :final_message]),
         {:ok, effort} <- effort(opts, @codex_efforts) do
      base = [
        backend: @backends["codex"],
        working_dir: cwd,
        approval_policy: :never,
        response_text: response_text
      ]

      base = if sandbox == :inherit, do: base, else: base ++ [sandbox: sandbox]
      base = if user_config == :ignore, do: base ++ [ignore_user_config: true], else: base

      base =
        if effort,
          do: base ++ [config_overrides: [~s(model_reasoning_effort="#{effort}")]],
          else: base

      {:ok, maybe_model(base, opts)}
    end
  end

  defp build_opts(provider, _opts), do: {:error, {:unknown_provider, provider}}

  defp claude_access_opts(:inherit), do: []

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

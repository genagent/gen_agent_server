defmodule GenAgentServer.Providers do
  @moduledoc """
  The provider names this server accepts and the backend options it uses for
  each.

  Claude defaults to plan permission mode and Codex to a read-only sandbox with
  approvals disabled. Callers can opt in to edit modes with the same narrow
  choices that profiles allow.
  """

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
    * `:claude_permission_mode` -- `:plan` (default) or `:accept_edits`.
    * `:model` -- model name passed to the CLI backends.
  """
  def backend_opts(provider, opts \\ [])

  def backend_opts("echo", _opts), do: {:ok, [backend: @backends["echo"]]}

  def backend_opts("claude", opts) do
    with {:ok, cwd} <- fetch_cwd(opts),
         {:ok, mode} <- choice(opts, :claude_permission_mode, [:plan, :accept_edits]) do
      {:ok, maybe_model([backend: @backends["claude"], cwd: cwd, permission_mode: mode], opts)}
    end
  end

  def backend_opts("codex", opts) do
    with {:ok, cwd} <- fetch_cwd(opts),
         {:ok, sandbox} <- choice(opts, :codex_sandbox, [:read_only, :workspace_write]) do
      base = [backend: @backends["codex"], cwd: cwd, sandbox: sandbox, approval_policy: :never]
      {:ok, maybe_model(base, opts)}
    end
  end

  def backend_opts(provider, _opts), do: {:error, {:unknown_provider, provider}}

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

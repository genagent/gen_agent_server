defmodule GenAgentServer.RuntimeConfig do
  @moduledoc """
  Application configuration read from `GEN_AGENT_SERVER_*` environment variables.

  A dependency's `config/runtime.exs` is not applied in the host, so this
  repository's runtime configuration and any host or extension project call
  the same function:

      # config/runtime.exs
      import Config
      config :gen_agent_server, GenAgentServer.RuntimeConfig.from_env!()

  Variables:

    * `GEN_AGENT_SERVER_PROVIDERS` -- comma-separated `echo`, `claude`, `codex`
      routes for the default instance (default `echo`)
    * `GEN_AGENT_SERVER_CWD` -- project directory for CLI providers (default
      the current directory)
    * `GEN_AGENT_SERVER_CONFIG` -- optional configuration file with named
      profiles
  """

  @backends %{
    "echo" => GenAgentEnsemble.Backends.Echo,
    "claude" => GenAgent.Backends.Claude,
    "codex" => GenAgent.Backends.Codex
  }

  @doc "Keyword configuration for `:gen_agent_server`. Raises `ArgumentError` on invalid values."
  @spec from_env!(%{String.t() => String.t()}) :: keyword()
  def from_env!(env \\ System.get_env()) do
    providers =
      env
      |> Map.get("GEN_AGENT_SERVER_PROVIDERS", "echo")
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)

    if providers == [] or Enum.any?(providers, &(&1 == "")) do
      raise ArgumentError, "GEN_AGENT_SERVER_PROVIDERS must name at least one provider"
    end

    if length(providers) != length(Enum.uniq(providers)) do
      raise ArgumentError, "GEN_AGENT_SERVER_PROVIDERS contains duplicate providers"
    end

    cwd = env |> Map.get("GEN_AGENT_SERVER_CWD", File.cwd!()) |> Path.expand()

    unless File.dir?(cwd) do
      raise ArgumentError, "GEN_AGENT_SERVER_CWD is not a directory: #{cwd}"
    end

    [
      session_name: "server/default",
      agents: Enum.map(providers, &agent(&1, cwd)),
      profile_file: Map.get(env, "GEN_AGENT_SERVER_CONFIG")
    ]
  end

  defp agent(provider, cwd) do
    backend =
      case Map.fetch(@backends, provider) do
        {:ok, module} -> module
        :error -> raise ArgumentError, "unknown provider: #{provider}"
      end

    backend_opts =
      case provider do
        "echo" ->
          [backend: backend]

        "claude" ->
          [backend: backend, working_dir: cwd, permission_mode: :plan]

        "codex" ->
          [
            backend: backend,
            working_dir: cwd,
            sandbox: :read_only,
            approval_policy: :never,
            ignore_user_config: true
          ]
      end

    {provider, GenAgentEnsemble.Agents.Simple, backend_opts}
  end
end

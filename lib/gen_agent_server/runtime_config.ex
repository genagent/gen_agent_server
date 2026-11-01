defmodule GenAgentServer.RuntimeConfig do
  @moduledoc """
  Application configuration read from `GEN_AGENT_SERVER_*` environment variables.

  A dependency's `config/runtime.exs` is not applied in the host, so this
  repository's runtime configuration and any host or extension project call
  the same function:

      # config/runtime.exs
      import Config
      config :gen_agent_server, GenAgentServer.RuntimeConfig.from_env!()

  CLI access inherits the server process user's CLI settings by omitting access
  overrides. This does not transfer transient client permissions. Headless
  sessions cannot answer prompts; Codex keeps approvals disabled. Access depends
  on CLI configuration and host permissions. Startup options use the shared
  private provider builder without application overrides; child environment
  cleanup runs when the instance starts.

  Variables:

    * `GEN_AGENT_SERVER_PROVIDERS` -- comma-separated `echo`, `claude`, `codex`
      routes for the default instance (default `echo`)
    * `GEN_AGENT_SERVER_CWD` -- project directory for CLI providers (default
      the current directory)
    * `GEN_AGENT_SERVER_CONFIG` -- optional configuration file with named
      profiles
  """

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
    unless GenAgentServer.Providers.known?(provider) do
      raise ArgumentError, "unknown provider: #{provider}"
    end

    {:ok, backend_opts} = GenAgentServer.Providers.startup_backend_opts(provider, cwd: cwd)
    {provider, GenAgentEnsemble.Agents.Simple, backend_opts}
  end
end

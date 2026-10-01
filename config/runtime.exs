import Config

providers =
  System.get_env("GEN_AGENT_SERVER_PROVIDERS", "echo")
  |> String.split(",", trim: true)
  |> Enum.map(&String.trim/1)

if providers == [] or Enum.any?(providers, &(&1 == "")) do
  raise ArgumentError, "GEN_AGENT_SERVER_PROVIDERS must name at least one provider"
end

if length(providers) != length(Enum.uniq(providers)) do
  raise ArgumentError, "GEN_AGENT_SERVER_PROVIDERS contains duplicate providers"
end

cwd = System.get_env("GEN_AGENT_SERVER_CWD", File.cwd!()) |> Path.expand()

unless File.dir?(cwd) do
  raise ArgumentError, "GEN_AGENT_SERVER_CWD is not a directory: #{cwd}"
end

backends = %{
  "echo" => GenAgentEnsemble.Backends.Echo,
  "claude" => GenAgent.Backends.Claude,
  "codex" => GenAgent.Backends.Codex
}

agents =
  for provider <- providers do
    backend =
      case Map.fetch(backends, provider) do
        {:ok, module} -> module
        :error -> raise ArgumentError, "unknown provider: #{provider}"
      end

    backend_opts =
      case provider do
        "echo" -> [backend: backend]
        "claude" -> [backend: backend, cwd: cwd, permission_mode: :plan]
        "codex" -> [backend: backend, cwd: cwd, sandbox: :read_only, approval_policy: :never]
      end

    {provider, GenAgentEnsemble.Agents.Simple, backend_opts}
  end

config :gen_agent_server,
  session_name: "server/default",
  agents: agents

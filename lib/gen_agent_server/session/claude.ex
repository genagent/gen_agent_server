defmodule GenAgentServer.Session.Claude do
  @moduledoc false
  # `GenAgentServer.Session` provider for `claude`, over `ClaudeWrapper.Session`.

  alias ClaudeWrapper.{Config, Result, Session}
  alias GenAgentServer.Providers

  @config_keys [:binary, :working_dir, :env, :timeout]

  def new(opts) do
    with {:ok, backend_opts} <-
           Providers.backend_opts("claude", provider_opts(opts)) do
      {config_opts, query_opts} =
        backend_opts
        |> Keyword.drop([:backend])
        |> Keyword.split(@config_keys)

      {:ok, Session.new(Config.new(config_opts), query_opts)}
    end
  end

  def session_id(session), do: Session.session_id(session)

  def run(session, prompt) do
    case Session.send(session, prompt) do
      {:ok, _session, %Result{is_error: true} = result} ->
        {:error, {:turn_failed, result.result}}

      {:ok, session, result} ->
        {:ok, session,
         %{
           text: result.result,
           usage: Result.usage(result),
           cost_usd: result.cost_usd,
           provider_session_id: Session.session_id(session)
         }}

      {:error, _} = error ->
        error
    end
  end

  defp provider_opts(opts) do
    access =
      case Keyword.get(opts, :access) do
        nil ->
          []

        "inherit" ->
          []

        value ->
          [
            claude_permission_mode:
              choice(value, Providers.access_choices(:claude_permission_mode))
          ]
      end

    effort = opts[:effort] && choice(opts[:effort], Providers.efforts("claude"))
    [cwd: opts[:cwd], model: opts[:model], effort: effort] ++ access
  end

  # Unknown strings pass through so `Providers` rejects them as invalid options.
  defp choice(value, allowed), do: Enum.find(allowed, value, &(Atom.to_string(&1) == value))
end

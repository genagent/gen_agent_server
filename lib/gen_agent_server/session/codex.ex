defmodule GenAgentServer.Session.Codex do
  @moduledoc false
  # `GenAgentServer.Session` provider for `codex`, over `CodexWrapper.Session`.

  alias CodexWrapper.{Config, JsonLineEvent, Session}
  alias GenAgentServer.Providers

  @config_keys [:binary, :working_dir, :env, :timeout, :idle_timeout_ms]

  def new(opts) do
    with {:ok, backend_opts} <-
           Providers.backend_opts("codex", provider_opts(opts)) do
      {config_opts, exec_opts} =
        backend_opts
        |> Keyword.drop([:backend, :response_text])
        |> rename(:config_overrides, :config)
        |> Keyword.split(@config_keys)

      {:ok, Session.new(Config.new(config_opts), exec_opts)}
    end
  end

  def session_id(session), do: Session.session_id(session)

  def run(session, prompt) do
    case Session.send(session, prompt) do
      {:ok, session, result} ->
        events = JsonLineEvent.parse_lines(result.stdout)

        case Enum.find(events, &(&1.event_type in ["turn.failed", "error"])) do
          nil ->
            {:ok, session,
             %{
               text: final_message(events),
               usage: usage(events),
               provider_session_id: Session.session_id(session)
             }}

          failed ->
            {:error, {:turn_failed, failed.data}}
        end

      {:error, {:exit, code, result}} ->
        {:error, {:exit, code, String.slice(result.stderr || "", -2_000, 2_000)}}

      {:error, _} = error ->
        error
    end
  end

  defp provider_opts(opts) do
    access =
      case Keyword.get(opts, :access) do
        nil -> []
        "inherit" -> []
        value -> [codex_sandbox: choice(value, Providers.access_choices(:codex_sandbox))]
      end

    effort = opts[:effort] && choice(opts[:effort], Providers.efforts("codex"))
    [cwd: opts[:cwd], model: opts[:model], effort: effort] ++ access
  end

  # Unknown strings pass through so `Providers` rejects them as invalid options.
  defp choice(value, allowed), do: Enum.find(allowed, value, &(Atom.to_string(&1) == value))

  defp rename(opts, from, to) do
    case Keyword.pop(opts, from) do
      {nil, opts} -> opts
      {value, opts} -> Keyword.put(opts, to, value)
    end
  end

  defp final_message(events) do
    events
    |> Enum.filter(
      &match?(
        %{event_type: "item.completed", data: %{"item" => %{"type" => "agent_message"}}},
        &1
      )
    )
    |> List.last()
    |> case do
      nil -> ""
      event -> event.data["item"]["text"]
    end
  end

  defp usage(events) do
    case Enum.filter(events, &(&1.event_type == "turn.completed")) |> List.last() do
      %{data: %{"usage" => usage}} -> usage
      _ -> nil
    end
  end
end

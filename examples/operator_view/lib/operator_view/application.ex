defmodule OperatorView.Application do
  @moduledoc false
  use Application

  # Only the observer's web tree runs here. The observed release stays the sole
  # owner of instances and agent work; this VM never starts GenAgentServer.
  @impl true
  def start(_type, _args) do
    settings = OperatorView.Settings.fetch!()

    if settings.transport == OperatorView.Transport.Release do
      OperatorView.Transport.Release.check_config!()
    end

    check_loopback!(Application.get_env(:operator_view, OperatorViewWeb.Endpoint, []))

    children = [
      {Phoenix.PubSub, name: OperatorView.PubSub},
      {Task.Supervisor, name: OperatorView.TaskSupervisor},
      OperatorViewWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: OperatorView.Supervisor)
  end

  @doc false
  def check_loopback!(endpoint_config) do
    case get_in(endpoint_config, [:http, :ip]) do
      {127, 0, 0, 1} -> :ok
      _other -> raise ArgumentError, "the operator view only binds 127.0.0.1"
    end
  end
end

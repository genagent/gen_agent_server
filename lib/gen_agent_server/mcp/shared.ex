defmodule GenAgentServer.MCP.Shared do
  @moduledoc """
  Opt-in shared HTTP MCP listener for startup-configured instances.
  Its temporary listener is isolated from the application's invocation owners.
  """
  use Supervisor
  alias GenAgentServer.Ops
  @tools ~w(instances agents status describe_instance invoke result ask)
  def tools, do: @tools

  def start_link(config), do: Supervisor.start_link(__MODULE__, config, name: __MODULE__)

  def child_spec(config) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [config]},
      type: :supervisor,
      restart: :temporary
    }
  end

  @impl true
  def init(config) do
    runtime =
      GenAgentServer.MCP.Shared.Server.runtime(
        authorization: {GenAgentServer.MCP.Shared.Authorization, %{instances: config.instances}}
      )

    opts = [
      name: GenAgentServer.MCP.Shared.Listener,
      runtime: runtime,
      ip: {127, 0, 0, 1},
      port: config.port,
      path: "/mcp",
      request_gate: {GenAgentServer.MCP.Shared.Gate, Map.to_list(config)},
      allowed_hosts: ["127.0.0.1:#{config.port}"],
      allowed_origin_hosts: ["127.0.0.1:#{config.port}"],
      max_connections: 32,
      max_concurrency: 8,
      max_queue: 16,
      max_header_bytes: 8192,
      max_body_bytes: 65_536,
      head_timeout: 2000,
      body_timeout: 2000,
      read_timeout: 2000,
      request_gate_timeout: 1000,
      request_timeout: 10_000,
      drain_timeout: 1000
    ]

    child =
      Supervisor.child_spec({Snodo.Transport.StreamableHTTP.Server, opts}, restart: :temporary)

    Supervisor.init([child], strategy: :one_for_one)
  end

  # The schema and Ops validation both reject extra keys; the context is supplied
  # by the gate, never a client argument. No default instance is selected here.
  def run(name, args, %{auth: %{shared_mcp: true, instances: instances}})
      when name in @tools and is_map(args) do
    outcome =
      cond do
        name == "instances" and args == %{} ->
          {:ok, %{instances: Enum.filter(GenAgentServer.instances(), &(&1 in instances))}}

        args["instance"] not in instances ->
          {:error, %{code: "not_authorized", message: "Instance is not allowed"}}

        name == "ask" ->
          ask(args)

        true ->
          Ops.call(name, args, source: :mcp)
      end

    outcome =
      case outcome do
        {:ok, data} when name != "instances" -> {:ok, Map.put(data, :instance, args["instance"])}
        other -> other
      end

    result(outcome)
  end

  def run(_, _, _), do: result({:error, %{code: "not_authorized", message: "Not authorized"}})

  defp ask(args) do
    timeout = Map.get(args, "timeout_ms", 1000)
    # Validate ask keys before submitting. Ops.invoke performs the other checks.
    if is_integer(timeout) and timeout in 0..5000 and
         Enum.all?(Map.keys(args), &(&1 in ~w(instance agent prompt timeout_ms))) do
      with {:ok, %{id: id}} <- Ops.call("invoke", Map.delete(args, "timeout_ms"), source: :mcp) do
        wait(args["instance"], id, System.monotonic_time(:millisecond) + timeout)
      end
    else
      {:error,
       %{code: "invalid_args", message: "ask wait must be 0..5000 ms; unknown keys are refused"}}
    end
  end

  defp wait(instance, id, deadline) do
    case Ops.call("result", %{"instance" => instance, "id" => id}) do
      {:ok, %{status: "pending"} = data} ->
        remaining = deadline - System.monotonic_time(:millisecond)

        if remaining <= 0 do
          {:ok, Map.put(data, :instance, instance)}
        else
          Process.sleep(min(10, remaining))
          wait(instance, id, deadline)
        end

      {:ok, data} ->
        {:ok, Map.put(data, :instance, instance)}

      error ->
        error
    end
  end

  defp result({:ok, data}),
    do: {:ok, data |> Jason.encode!() |> Jason.decode!() |> Snodo.Result.structured()}

  defp result({:error, %{code: code, message: message}}),
    do: {:ok, Snodo.Result.error("#{code}: #{message}")}
end

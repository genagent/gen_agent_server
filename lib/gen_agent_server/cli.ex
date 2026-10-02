defmodule GenAgentServer.CLI do
  @moduledoc """
  Small local command entry point for inspecting and asking configured agents.

  Run with `mix gen_agent_server ...` or from a running release with `rpc`.
  """

  def run(args, source \\ :local_cli)

  def run(["instances"], _source) do
    {:ok, Enum.join(GenAgentServer.instances(), "\n")}
  end

  def run(["jobs"], _source) do
    {:ok, Enum.join(GenAgentServer.Dispatch.jobs(), "\n")}
  end

  def run(["job", name], _source) do
    case GenAgentServer.Dispatch.latest(name) do
      {:ok, nil} -> {:ok, "never run"}
      {:ok, id} -> {:ok, id}
      error -> error
    end
  end

  def run(["run-job", name], _source) do
    if name in GenAgentServer.Dispatch.jobs() do
      GenAgentServer.Scheduler.run_job(String.to_existing_atom(name))
      {:ok, "queued"}
    else
      {:error, :unknown_job}
    end
  end

  def run(["--instance", instance | args], source) when args != [] do
    run_instance(instance, args, source)
  end

  def run(args, source), do: run_instance(GenAgentServer.session_name(), args, source)

  defp run_instance(instance, ["agents"], _source) do
    with {:ok, names} <- GenAgentServer.agents(instance), do: {:ok, Enum.join(names, "\n")}
  end

  defp run_instance(instance, ["status"], _source) do
    with {:ok, status} <- GenAgentServer.status(instance),
         do: {:ok, inspect(status, pretty: true)}
  end

  defp run_instance(instance, ["ask", agent | words], source) when words != [] do
    with {:ok, response} <-
           GenAgentServer.ask_instance(instance, agent, Enum.join(words, " "), source: source) do
      {:ok, presented_answer(response)}
    end
  end

  defp run_instance(instance, ["invoke", agent | words], source) when words != [] do
    GenAgentServer.invoke(instance, agent, Enum.join(words, " "), source: source)
  end

  defp run_instance(instance, ["result", id], _source) do
    case GenAgentServer.result(instance, id) do
      {:ok, :pending} -> {:ok, "pending"}
      {:ok, :completed, response} -> {:ok, presented_answer(response)}
      {:ok, :failed, reason} -> {:error, reason}
      error -> error
    end
  end

  defp run_instance(_instance, _args, _source), do: {:error, :usage}

  def main(args, source \\ :local_cli) do
    :ok = :io.setopts(:standard_io, encoding: :unicode)
    :ok = :io.setopts(:standard_error, encoding: :unicode)

    case run(args, source) do
      {:ok, output} ->
        IO.puts(output)
        :ok

      {:error, reason} ->
        Mix.raise("error: #{error_message(args, reason)}")
    end
  end

  # A release RPC cannot signal an ordinary CLI error by raising: the release
  # prints a stack trace before the local Mix task can format the error. Keep
  # the result as data across the RPC and let the local task choose its exit code.
  def remote_main(args) do
    :ok = :io.setopts(:standard_io, encoding: :unicode)

    response =
      case run(args, :remote_cli) do
        {:ok, output} -> %{"ok" => output}
        {:error, reason} -> %{"error" => error_message(args, reason)}
      end

    IO.puts(Jason.encode!(response))
    :ok
  end

  def error_message(args, reason)

  def error_message(args, :not_found) do
    case command(args) do
      {["result", id], instance} -> "invocation #{id} not found in instance #{instance}"
      {_command, instance} -> "requested item not found in instance #{instance}"
    end
  end

  def error_message(args, :instance_not_found) do
    {_command, instance} = command(args)
    "instance #{instance} not found"
  end

  def error_message(args, :busy) do
    {_command, instance} = command(args)
    "instance #{instance} is busy"
  end

  def error_message(args, :unknown_job) do
    case command(args) do
      {[command, name], _instance} when command in ["job", "run-job"] ->
        "job #{name} not found"

      _ ->
        "job not found"
    end
  end

  def error_message(_args, :usage),
    do:
      "usage: gen_agent_server instances | jobs | job NAME | run-job NAME | [--instance NAME] agents | status | ask PROVIDER PROMPT | invoke PROVIDER PROMPT | result ID"

  def error_message(args, {:unknown_agent, name}) do
    {_command, instance} = command(args)
    "agent #{name} not found in instance #{instance}"
  end

  def error_message(_args, reason), do: "GenAgent request failed: #{inspect(reason)}"

  # A response may contain more than one completed assistant message. Keep
  # Response.text intact for API consumers; use the explicit presentation
  # field when the installed core version provides it.
  defp presented_answer(response), do: Map.get(response, :final_message) || response.text

  defp command(["--instance", instance | args]), do: {args, instance}
  defp command(args), do: {args, GenAgentServer.session_name()}
end

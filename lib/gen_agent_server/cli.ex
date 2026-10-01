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
      {:ok, response.text}
    end
  end

  defp run_instance(instance, ["invoke", agent | words], source) when words != [] do
    GenAgentServer.invoke(instance, agent, Enum.join(words, " "), source: source)
  end

  defp run_instance(instance, ["result", id], _source) do
    case GenAgentServer.result(instance, id) do
      {:ok, :pending} -> {:ok, "pending"}
      {:ok, :completed, response} -> {:ok, response.text}
      {:ok, :failed, reason} -> {:error, reason}
      error -> error
    end
  end

  defp run_instance(_instance, _args, _source), do: {:error, :usage}

  def main(args, source \\ :local_cli) do
    case run(args, source) do
      {:ok, output} ->
        IO.puts(output)
        :ok

      {:error, :usage} ->
        raise ArgumentError,
              "usage: gen_agent_server instances | jobs | job NAME | run-job NAME | [--instance NAME] agents | status | ask PROVIDER PROMPT | invoke PROVIDER PROMPT | result ID"

      {:error, reason} ->
        raise RuntimeError, "GenAgent request failed: #{inspect(reason)}"
    end
  end
end

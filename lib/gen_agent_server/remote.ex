defmodule GenAgentServer.Remote do
  @moduledoc false

  @control_timeout_ms 30_000
  @ask_timeout_ms 3_600_000

  @doc false
  def expression(args) when is_list(args) do
    encoded_args = inspect(args, limit: :infinity, printable_limit: :infinity)
    "GenAgentServer.CLI.main(#{encoded_args}, :remote_cli)"
  end

  @doc false
  def run(release_bin, args, opts \\ []) when is_binary(release_bin) and is_list(args) do
    timeout_ms = Keyword.get(opts, :timeout_ms, timeout_for(args))

    port =
      Port.open({:spawn_executable, release_bin}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: ["rpc", expression(args)]
      ])

    deadline = System.monotonic_time(:millisecond) + timeout_ms
    collect(port, deadline, [])
  end

  defp timeout_for(["--instance", _instance, "ask" | _]), do: ask_timeout()
  defp timeout_for(["ask" | _]), do: ask_timeout()
  defp timeout_for(_args), do: env_timeout("GEN_AGENT_SERVER_RPC_TIMEOUT_MS", @control_timeout_ms)

  defp ask_timeout,
    do: env_timeout("GEN_AGENT_SERVER_ASK_RPC_TIMEOUT_MS", @ask_timeout_ms)

  defp env_timeout(variable, default) do
    case System.get_env(variable) do
      nil ->
        default

      raw ->
        case Integer.parse(raw) do
          {value, ""} when value > 0 -> value
          _ -> raise ArgumentError, "#{variable} must be a positive integer in milliseconds"
        end
    end
  end

  defp collect(port, deadline, output) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, data}} ->
        collect(port, deadline, [data | output])

      {^port, {:exit_status, status}} ->
        {output |> Enum.reverse() |> IO.iodata_to_binary(), status}
    after
      remaining ->
        stop_process_tree(port)
        {:error, :timeout}
    end
  end

  defp stop_process_tree(port) do
    case Port.info(port, :os_pid) do
      {:os_pid, pid} ->
        pids = process_tree(pid)
        Enum.each(pids, &signal(&1, "-TERM"))
        Process.sleep(100)
        Enum.each(pids, &signal(&1, "-KILL"))

      nil ->
        :ok
    end

    try do
      Port.close(port)
    rescue
      ArgumentError -> :ok
    end
  end

  defp process_tree(root) do
    case System.cmd("ps", ["-eo", "pid=,ppid="], stderr_to_stdout: true) do
      {listing, 0} ->
        children =
          listing
          |> String.split("\n", trim: true)
          |> Enum.reduce(%{}, fn line, acc ->
            case String.split(line) do
              [pid, parent] ->
                Map.update(
                  acc,
                  String.to_integer(parent),
                  [String.to_integer(pid)],
                  &[String.to_integer(pid) | &1]
                )

              _ ->
                acc
            end
          end)

        descendants(root, children) ++ [root]

      _ ->
        [root]
    end
  end

  defp descendants(parent, children) do
    Enum.flat_map(Map.get(children, parent, []), fn pid -> descendants(pid, children) ++ [pid] end)
  end

  defp signal(pid, kind) do
    _ = System.cmd("kill", [kind, Integer.to_string(pid)], stderr_to_stdout: true)
    :ok
  end
end

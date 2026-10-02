defmodule GenAgentServer.Remote do
  @moduledoc false

  @control_timeout_ms 30_000
  @ask_timeout_ms 3_600_000

  @doc false
  def expression(args) when is_list(args) do
    encoded_args = inspect(args, limit: :infinity, printable_limit: :infinity)
    "GenAgentServer.CLI.remote_main(#{encoded_args})"
  end

  @doc false
  def decode_response(output) when is_binary(output) do
    case Jason.decode(String.trim(output)) do
      {:ok, %{"ok" => text}} when is_binary(text) -> {:ok, text}
      {:ok, %{"error" => message}} when is_binary(message) -> {:error, message}
      _ -> {:error, :invalid_response}
    end
  end

  @doc false
  def run(release_bin, args, opts \\ []) when is_binary(release_bin) and is_list(args) do
    timeout_ms = Keyword.get(opts, :timeout_ms, timeout_for(args))
    run_expression(release_bin, expression(args), timeout_ms: timeout_ms)
  end

  @doc false
  def run_expression(release_bin, expression, opts \\ []) when is_binary(expression) do
    timeout_ms =
      opts
      |> Keyword.get_lazy(:timeout_ms, fn ->
        env_timeout("GEN_AGENT_SERVER_RPC_TIMEOUT_MS", @control_timeout_ms)
      end)
      |> validate_timeout!()

    port =
      Port.open({:spawn_executable, release_bin}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: ["rpc", expression]
      ])

    os_pid =
      case Port.info(port, :os_pid) do
        {:os_pid, pid} -> pid
        nil -> nil
      end

    deadline = System.monotonic_time(:millisecond) + timeout_ms
    collect(port, os_pid, deadline, [])
  end

  defp validate_timeout!(value) when is_integer(value) and value > 0, do: value

  defp validate_timeout!(_value),
    do: raise(ArgumentError, "timeout_ms must be a positive integer")

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

  defp collect(port, os_pid, deadline, output) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, data}} ->
        collect(port, os_pid, deadline, [data | output])

      {^port, {:exit_status, status}} ->
        {output |> Enum.reverse() |> IO.iodata_to_binary(), status}
    after
      remaining ->
        stop_process_tree(port, os_pid)
        {:error, :timeout}
    end
  end

  defp stop_process_tree(port, os_pid) do
    if is_integer(os_pid) and Port.info(port) do
      pids = process_tree(os_pid)
      Enum.each(pids, &signal_if_same(&1, "-TERM"))
      Process.sleep(100)
      Enum.each(pids, &signal_if_same(&1, "-KILL"))
    end

    try do
      Port.close(port)
    rescue
      ArgumentError -> :ok
    end

    drain_port_messages(port)
  end

  defp process_tree(root) do
    case System.cmd("ps", ["-eo", "pid=,ppid=,lstart="], stderr_to_stdout: true) do
      {listing, 0} ->
        processes = parse_processes(listing)

        if Map.has_key?(processes, root),
          do: descendants(root, processes) ++ [{root, elem(processes[root], 1)}],
          else: []

      _ ->
        []
    end
  end

  defp parse_processes(listing) do
    listing
    |> String.split("\n", trim: true)
    |> Enum.reduce(%{}, fn line, acc ->
      case String.split(line) do
        [pid, parent | started] when started != [] ->
          Map.put(
            acc,
            String.to_integer(pid),
            {String.to_integer(parent), Enum.join(started, " ")}
          )

        _ ->
          acc
      end
    end)
  end

  defp descendants(parent, processes) do
    processes
    |> Enum.filter(fn {_pid, {ppid, _identity}} -> ppid == parent end)
    |> Enum.flat_map(fn {pid, {_ppid, identity}} ->
      descendants(pid, processes) ++ [{pid, identity}]
    end)
  end

  defp signal_if_same({pid, identity}, kind) do
    if process_identity(pid) == identity do
      _ = System.cmd("kill", [kind, Integer.to_string(pid)], stderr_to_stdout: true)
    end

    :ok
  end

  defp process_identity(pid) do
    case System.cmd("ps", ["-o", "lstart=", "-p", Integer.to_string(pid)], stderr_to_stdout: true) do
      {started, 0} -> started |> String.split() |> Enum.join(" ")
      _ -> nil
    end
  end

  defp drain_port_messages(port) do
    receive do
      {^port, {:data, _data}} -> drain_port_messages(port)
      {^port, {:exit_status, _status}} -> :ok
    after
      100 -> :ok
    end
  end
end

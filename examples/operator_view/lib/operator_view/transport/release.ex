defmodule OperatorView.Transport.Release do
  @moduledoc """
  Reads from one already running `gen_agent_server` release through the
  server's existing `GenAgentServer.Ops.Remote.call/4`.

  The release executable comes from operator configuration
  (`OPERATOR_VIEW_RELEASE_BIN`). The release node name and cookie come from
  this process's environment (`RELEASE_NODE`, and `RELEASE_COOKIE` when set),
  as for `mix gen_agent_server.ops --remote`. Each read runs one short-lived
  release `rpc` control VM, stopped if it exceeds `timeout_ms`.

  The page stops a refresh worker when the page closes or the refresh passes
  its deadline. Stopping the process that owns the release Port would skip
  `Ops.Remote`'s own timeout cleanup, and closing a Port does not stop its
  operating-system process. So each read runs in its own `rpc` process, watched
  by a supervised guard that is not linked to the caller. When the caller stops
  first, the guard suspends the `rpc` process, stops the operating-system
  process tree of its Port (TERM, then KILL), and only then kills it. If the
  guard itself is killed, the unlinked `rpc` process still applies
  `Ops.Remote`'s timeout and cleanup.
  """

  @behaviour OperatorView.Transport

  @impl true
  def call(operation, args, timeout_ms) do
    release_bin = release_bin!()
    caller = self()
    ref = make_ref()
    request = {release_bin, operation, args, timeout_ms}
    watch = fn -> guard(caller, ref, request) end
    {:ok, guard} = Task.Supervisor.start_child(OperatorView.TaskSupervisor, watch)
    monitor = Process.monitor(guard)

    receive do
      {^ref, result} ->
        Process.demonitor(monitor, [:flush])
        result

      {:DOWN, ^monitor, :process, _guard, _reason} ->
        rpc_crashed()
    end
  end

  defp guard(caller, ref, request) do
    # Trapping exits lets a supervisor shutdown run the same cleanup.
    Process.flag(:trap_exit, true)
    caller_monitor = Process.monitor(caller)
    guard = self()
    work = fn -> send(guard, {:rpc_result, self(), rpc(request)}) end
    {rpc, rpc_monitor} = spawn_monitor(work)

    receive do
      {:rpc_result, ^rpc, result} -> send(caller, {ref, result})
      {:DOWN, ^rpc_monitor, :process, ^rpc, _reason} -> send(caller, {ref, rpc_crashed()})
      {:DOWN, ^caller_monitor, :process, ^caller, _reason} -> stop_rpc(rpc)
      {:EXIT, _from, _reason} -> stop_rpc(rpc)
    end
  end

  defp rpc({release_bin, operation, args, timeout_ms}) do
    GenAgentServer.Ops.Remote.call(release_bin, operation, args, timeout_ms: timeout_ms)
  rescue
    # Port.open raises when the executable is missing or cannot be run.
    ErlangError -> {:error, %{code: "release_unavailable"}}
  end

  defp rpc_crashed, do: {:error, %{code: "rpc_failed"}}

  # Suspended, the rpc process cannot open a Port after the list below is taken.
  # It is resumed only after the kill signal is queued, and a process handles
  # pending signals before it runs any more code, so it never runs again.
  defp stop_rpc(rpc) do
    if suspend(rpc) do
      rpc |> port_os_pids() |> Enum.flat_map(&process_tree/1) |> stop_processes()
      Process.exit(rpc, :kill)
      resume(rpc)
    else
      Process.exit(rpc, :kill)
    end

    :ok
  end

  defp suspend(pid) do
    :erlang.suspend_process(pid)
  rescue
    ArgumentError -> false
  end

  defp resume(pid) do
    :erlang.resume_process(pid)
  rescue
    ArgumentError -> false
  end

  defp port_os_pids(owner) do
    for port <- Port.list(),
        Port.info(port, :connected) == {:connected, owner},
        {:os_pid, os_pid} <- [Port.info(port, :os_pid)],
        is_integer(os_pid),
        do: os_pid
  end

  defp stop_processes([]), do: :ok

  defp stop_processes(processes) do
    Enum.each(processes, &signal_if_same(&1, "-TERM"))
    Process.sleep(100)
    Enum.each(processes, &signal_if_same(&1, "-KILL"))
  end

  # The root and its descendants, each with its start time, so a recycled
  # process ID is never signalled.
  defp process_tree(root) do
    case System.cmd("ps", ["-eo", "pid=,ppid=,lstart="], stderr_to_stdout: true) do
      {listing, 0} ->
        processes = parse_processes(listing)

        case Map.fetch(processes, root) do
          {:ok, {_parent, started}} -> descendants(root, processes) ++ [{root, started}]
          :error -> []
        end

      _failed ->
        []
    end
  end

  defp parse_processes(listing) do
    listing
    |> String.split("\n", trim: true)
    |> Enum.reduce(%{}, fn line, acc ->
      with [pid, parent | started] when started != [] <- String.split(line),
           {pid, ""} <- Integer.parse(pid),
           {parent, ""} <- Integer.parse(parent) do
        Map.put(acc, pid, {parent, Enum.join(started, " ")})
      else
        _other -> acc
      end
    end)
  end

  defp descendants(parent, processes) do
    for {pid, {^parent, started}} <- processes,
        process <- descendants(pid, processes) ++ [{pid, started}],
        do: process
  end

  defp signal_if_same({pid, started}, signal) do
    pid = Integer.to_string(pid)

    case System.cmd("ps", ["-o", "lstart=", "-p", pid], stderr_to_stdout: true) do
      {current, 0} ->
        if current |> String.split() |> Enum.join(" ") == started do
          System.cmd("kill", [signal, pid], stderr_to_stdout: true)
        end

      _gone ->
        :ok
    end
  end

  @doc "Check the configured executable when the observer starts."
  def check_config! do
    path = release_bin!()

    unless Path.type(path) == :absolute and File.regular?(path) do
      raise ArgumentError, "OPERATOR_VIEW_RELEASE_BIN must be an absolute executable path"
    end

    :ok
  end

  defp release_bin! do
    case Application.get_env(:operator_view, :release_bin) do
      path when is_binary(path) and path != "" -> path
      _other -> raise ArgumentError, "OPERATOR_VIEW_RELEASE_BIN is not configured"
    end
  end
end

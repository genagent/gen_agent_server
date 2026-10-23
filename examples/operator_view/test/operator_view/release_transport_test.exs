defmodule OperatorView.ReleaseTransportTest do
  use OperatorView.OperatorCase, async: false

  alias OperatorView.Reader
  alias OperatorView.Transport.Release

  # Each test writes a stand-in release executable. It logs the rpc expression
  # it receives, then runs `body`, as `bin/gen_agent_server rpc EXPR` would.
  setup do
    dir = Path.join(System.tmp_dir!(), "operator-view-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    {:ok, dir: dir}
  end

  defp fake_release(dir, body) do
    log = Path.join(dir, "rpc.log")
    bin = Path.join(dir, "gen_agent_server")
    File.write!(bin, "#!/bin/sh\nprintf '%s\\n' \"$2\" >> '#{log}'\n" <> body)
    File.chmod!(bin, 0o755)
    configure(release_bin: bin)
    log
  end

  test "reads use Ops.Remote rpc with fixed operations and arguments", %{dir: dir} do
    envelope = ~s({"ok":true,"data":{"instance":"alpha","invocations":[]}})
    log = fake_release(dir, "echo 'release log line'\necho '#{envelope}'\n")

    assert {:ok, []} = Reader.invocations(Release, "alpha", 2_000)
    args = %{"instance" => "alpha", "limit" => 50}
    assert File.read!(log) == GenAgentServer.Ops.Remote.expression("invocations", args) <> "\n"
  end

  test "release failures become fixed codes", %{dir: dir} do
    fake_release(dir, "echo '#{dir} failure output'\nexit 3\n")
    assert {:error, :release_unavailable} = Reader.instances(Release, ["alpha"], 2_000)

    fake_release(dir, "echo 'not an envelope'\n")
    assert {:error, :bad_output} = Reader.instances(Release, ["alpha"], 2_000)

    error = ~s({"ok":false,"error":{"code":"instance_not_found","message":"gone"}})
    fake_release(dir, "echo '#{error}'\n")
    assert {:error, :instance_not_found} = Reader.status(Release, "alpha", 2_000)

    fake_release(dir, "exec sleep 5\n")
    assert {:error, :timeout} = Reader.instances(Release, ["alpha"], 200)

    configure(release_bin: Path.join(dir, "missing"))
    assert {:error, :release_unavailable} = Reader.instances(Release, ["alpha"], 2_000)
  end

  # A stalled release rpc with a child process. Both write their OS process IDs.
  defp stalled_release(dir) do
    fake_release(dir, """
    sleep 30 &
    echo $! > '#{dir}/child.pid'
    echo $$ > '#{dir}/root.pid'
    wait
    """)
  end

  defp await_os_pids(dir) do
    root = Path.join(dir, "root.pid")
    assert eventually(fn -> match?({:ok, <<_, _::binary>>}, File.read(root)) end)

    pids =
      for name <- ["root.pid", "child.pid"] do
        {pid, _rest} = dir |> Path.join(name) |> File.read!() |> Integer.parse()
        pid
      end

    assert Enum.all?(pids, &os_alive?/1)
    pids
  end

  defp os_alive?(pid) do
    {_out, status} = System.cmd("kill", ["-0", Integer.to_string(pid)], stderr_to_stdout: true)
    status == 0
  end

  defp settled?(pids), do: eventually(fn -> not Enum.any?(pids, &os_alive?/1) end)

  test "stopping the caller stops the release rpc process tree", %{dir: dir} do
    stalled_release(dir)
    {:ok, caller} = Task.start(fn -> Release.call("instances", %{}, 30_000) end)
    pids = await_os_pids(dir)

    Process.exit(caller, :kill)
    assert settled?(pids)
  end

  test "closing the page during a read stops the release rpc process tree", %{dir: dir} do
    Process.flag(:trap_exit, true)
    stalled_release(dir)
    configure(transport: Release, rpc_timeout_ms: 30_000, refresh_deadline_ms: 60_000)

    {:ok, view, _html} = live(operator_conn(), "/?instance=alpha")
    pids = await_os_pids(dir)

    GenServer.stop(view.pid, {:shutdown, :closed})
    assert settled?(pids)
  end

  test "a refresh deadline stops the release rpc process tree", %{dir: dir} do
    stalled_release(dir)
    configure(transport: Release, rpc_timeout_ms: 30_000, refresh_deadline_ms: 500)

    {:ok, view, _html} = live(operator_conn(), "/?instance=alpha")
    pids = await_os_pids(dir)

    assert eventually(fn -> render(view) =~ "release read timed out" end)
    assert settled?(pids)
  end

  test "the page shows an unavailable release without its path or output", %{dir: dir} do
    fake_release(dir, "echo '#{dir} failure output'\nexit 3\n")
    configure(transport: Release, rpc_timeout_ms: 2_000, refresh_deadline_ms: 9_000)

    {:ok, view, _html} = live(operator_conn(), "/?instance=alpha")
    assert eventually(fn -> render(view) =~ "release unavailable" end)

    html = render(view)
    refute html =~ dir
    refute html =~ "failure output"
    assert has_element?(view, "#paused")
  end
end

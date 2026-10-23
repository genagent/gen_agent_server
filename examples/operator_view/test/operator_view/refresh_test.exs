defmodule OperatorView.RefreshTest do
  use OperatorView.OperatorCase, async: false

  alias OperatorView.FakeRelease

  @full_alpha [
    {"instances", %{}},
    {"describe_instance", %{"instance" => "alpha"}},
    {"status", %{"instance" => "alpha"}},
    {"invocations", %{"instance" => "alpha", "limit" => 50}}
  ]

  setup do
    alpha = instance_data("alpha", [summary("inv-alpha-1", "pending")])
    beta = instance_data("beta", [summary("inv-beta-1", "completed")])
    data = %{"alpha" => alpha, "beta" => beta}
    start_supervised!({FakeRelease, owner: self(), instances: ["alpha", "beta"], data: data})
    configure(transport: FakeRelease, instances: ["alpha", "beta", "gamma"])
    :ok
  end

  defp gate, do: FakeRelease.update(&%{&1 | mode: :gate})
  defp answer, do: FakeRelease.update(&%{&1 | mode: :reply})
  defp fail_with(code), do: FakeRelease.update(&%{&1 | mode: {:error, code}})

  test "the disconnected render reads nothing; the connected mount reads one full snapshot" do
    html = operator_conn() |> get("/?instance=alpha") |> html_response(200)
    assert html =~ "Not read yet."
    assert drain_calls() == []

    {:ok, view, _html} = live(operator_conn(), "/?instance=alpha")
    assert drain_calls() == @full_alpha

    html = render(view)
    assert html =~ "inv-alpha-1"
    assert html =~ "Up to 50 retained invocations"
    refute html =~ "inv-beta-1"
    refute has_element?(view, "#paused")
  end

  test "one refresh runs at a time and manual refreshes coalesce while it is busy" do
    gate()
    {:ok, view, _html} = live(operator_conn(), "/?instance=alpha")
    assert_receive {:release_call, "instances", %{}}

    render_click(view, "refresh")
    render_click(view, "refresh")
    assert drain_calls() == []
    assert FakeRelease.gated() == 1

    answer()
    FakeRelease.release()

    # The rest of the first refresh, then exactly one coalesced full refresh.
    assert drain_calls() == tl(@full_alpha) ++ @full_alpha
  end

  test "polling reads status and summaries only, after the previous refresh finishes" do
    configure(refresh_interval_ms: 150)
    {:ok, _view, _html} = live(operator_conn(), "/?instance=alpha")
    assert drain_calls(30) == @full_alpha

    assert_receive {:release_call, "status", %{"instance" => "alpha"}}, 500
    assert_receive {:release_call, "invocations", %{"instance" => "alpha", "limit" => 50}}
    refute_received {:release_call, "instances", _args}
    refute_received {:release_call, "describe_instance", _args}
  end

  test "a stalled read marks data stale, pauses polling, and Refresh recovers" do
    configure(refresh_interval_ms: 50)
    {:ok, view, _html} = live(operator_conn(), "/?instance=alpha")
    assert eventually(fn -> render(view) =~ "inv-alpha-1" end)

    gate()
    assert eventually(fn -> has_element?(view, "#paused") end)
    html = render(view)
    assert html =~ "Stale: showing data read at"
    assert html =~ "release read timed out"
    assert html =~ "inv-alpha-1"

    _ = drain_calls()
    assert drain_calls(300) == []

    answer()
    render_click(view, "refresh")
    assert eventually(fn -> not (render(view) =~ "Stale:") end)
    refute has_element?(view, "#paused")
  end

  test "release errors keep prior data stale and never show release output" do
    {:ok, view, _html} = live(operator_conn(), "/?instance=alpha")
    assert eventually(fn -> render(view) =~ "inv-alpha-1" end)

    for {code, label} <- [
          {"rpc_timeout", "release read timed out"},
          {"rpc_failed", "release unavailable"},
          {"rpc_bad_output", "unreadable release output"}
        ] do
      _ = drain_calls(30)
      fail_with(code)
      render_click(view, "refresh")
      assert eventually(fn -> has_element?(view, "#paused") end)

      # The refresh stops at its first failed read.
      assert drain_calls() == [{"instances", %{}}]

      html = render(view)
      assert html =~ label
      assert html =~ "inv-alpha-1"
      refute html =~ "/private/release"

      answer()
      render_click(view, "refresh")
      assert eventually(fn -> not (render(view) =~ "Stale:") end)
      refute has_element?(view, "#paused")
    end
  end

  test "a reply for a previous selection never overwrites the current instance" do
    gate()
    {:ok, view, _html} = live(operator_conn(), "/?instance=alpha")
    assert_receive {:release_call, "instances", %{}}

    render_change(view, "select", %{"instance" => "beta"})
    assert_patch(view, "/?instance=beta")

    answer()
    FakeRelease.release()

    assert eventually(fn -> render(view) =~ "inv-beta-1" end)
    refute render(view) =~ "inv-alpha-1"
    assert {"invocations", %{"instance" => "beta", "limit" => 50}} in drain_calls()
  end

  test "closing the page stops its refresh worker" do
    Process.flag(:trap_exit, true)
    gate()
    {:ok, view, _html} = live(operator_conn(), "/?instance=alpha")
    assert_receive {:release_call, "instances", %{}}

    [worker] = FakeRelease.waiting_pids()
    ref = Process.monitor(worker)
    GenServer.stop(view.pid, {:shutdown, :closed})

    assert_receive {:DOWN, ^ref, :process, ^worker, _reason}, 1_000
  end

  test "an allowlisted instance that is not running is shown as unavailable" do
    {:ok, view, _html} = live(operator_conn(), "/?instance=gamma")
    selector = ~s(li[data-instance="gamma"][data-state="not_running"])

    assert eventually(fn -> has_element?(view, selector) end)
    assert render(view) =~ "Instance not running in the release"
    refute has_element?(view, "#paused")
  end

  test "an instance that stops is cleared rather than shown as finished" do
    {:ok, view, _html} = live(operator_conn(), "/?instance=alpha")
    assert eventually(fn -> render(view) =~ "inv-alpha-1" end)

    FakeRelease.update(fn state -> %{state | instances: ["beta"]} end)
    render_click(view, "refresh")

    assert eventually(fn -> render(view) =~ "Instance not running in the release" end)
    refute render(view) =~ "inv-alpha-1"
    refute has_element?(view, "#no-invocations")
  end

  test "unknown and strategy-specific fields are shown as unknown or by name only" do
    status = %{"strategy" => "Custom", "queue_depth" => 314_159, "pending" => ["t1", "t2"]}
    FakeRelease.update(&put_in(&1, [:data, "alpha", "status"], status))

    {:ok, view, _html} = live(operator_conn(), "/?instance=alpha")
    assert eventually(fn -> has_element?(view, ~s(dd[data-field="pending"]), "2") end)

    assert has_element?(view, ~s(dd[data-field="in_flight"]), "unknown")
    assert has_element?(view, ~s(dd[data-field="other"]), "queue_depth")
    refute render(view) =~ "314159"
    assert render(view) =~ "route names only"
    assert has_element?(view, ~s(td[data-route-field="provider"]), "unknown")
  end

  test "the page offers only read events and ignores unlisted instances" do
    {:ok, view, html} = live(operator_conn(), "/?instance=secret")
    assert has_element?(view, "#rejected")
    refute has_element?(view, "#invocations")

    pattern = ~r/phx-(?:click|change|submit)="([^"]+)"/
    events = Regex.scan(pattern, html, capture: :all_but_first)
    assert events |> List.flatten() |> Enum.uniq() |> Enum.sort() == ["refresh", "select"]

    render_change(view, "select", %{"instance" => "other-secret"})
    render_hook(view, "cancel", %{"id" => "inv-alpha-1"})
    render_hook(view, "invoke", %{"agent" => "worker", "prompt" => "x"})
    assert has_element?(view, "#rejected")

    calls = assert_only_reads(["alpha", "beta", "gamma"])
    rejected = ["secret", "other-secret"]
    refute Enum.any?(calls, fn {_operation, args} -> args["instance"] in rejected end)
  end
end

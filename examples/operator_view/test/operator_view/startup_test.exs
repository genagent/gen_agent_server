defmodule OperatorView.StartupTest do
  use OperatorView.OperatorCase, async: false

  test "the observer starts only its own web tree, not the server application" do
    boot = :persistent_term.get({:operator_view_test, :boot})

    refute :gen_agent_server in boot.applications
    refute :gen_agent_ensemble in boot.applications
    assert boot.registry == nil
    refute :gen_agent_server in Application.spec(:operator_view, :applications)

    children = Supervisor.which_children(OperatorView.Supervisor)
    assert length(children) == 3
    assert Enum.any?(children, &match?({OperatorViewWeb.Endpoint, _pid, _type, _modules}, &1))
  end

  test "the server application and its release metadata gain no Phoenix dependency" do
    server_dir = Mix.Project.deps_paths() |> Map.fetch!(:gen_agent_server)
    server_mix = File.read!(Path.join(server_dir, "mix.exs"))
    _ = Application.load(:gen_agent_server)
    server_apps = Application.spec(:gen_agent_server, :applications)

    for dependency <- [:phoenix, :phoenix_live_view, :phoenix_html, :bandit, :plug] do
      refute dependency in server_apps
      refute server_mix =~ ":#{dependency},"
    end
  end

  test "the endpoint binds loopback only and starts no listener in tests" do
    config = Application.get_env(:operator_view, OperatorViewWeb.Endpoint)
    assert :ok = OperatorView.Application.check_loopback!(config)
    assert config[:server] == false

    assert_raise ArgumentError, fn ->
      OperatorView.Application.check_loopback!(http: [ip: {0, 0, 0, 0}, port: 4075])
    end
  end

  test "settings reject an empty, oversized or invalid allowlist and a short token" do
    for instances <- [[], nil, ["ok", "ok"], ["bad name"], Enum.map(1..17, &"i#{&1}")] do
      configure(instances: instances)
      assert_raise ArgumentError, fn -> OperatorView.Settings.fetch!() end
    end

    configure(instances: ["server/default", "review"], token: "short")
    assert_raise ArgumentError, fn -> OperatorView.Settings.fetch!() end

    configure(token: String.duplicate("t", 24))
    assert %{instances: ["server/default", "review"]} = OperatorView.Settings.fetch!()
  end
end

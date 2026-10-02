defmodule GenAgentServerTest do
  use ExUnit.Case
  import ExUnit.CaptureIO
  import ExUnit.CaptureLog

  defmodule ErrorBackend do
    @behaviour GenAgent.Backend

    def start_session(_opts), do: {:ok, %{}}
    def prompt(session, _prompt), do: {:error, {:fixture_failure, session}}
    def update_session(session, _event), do: session
    def terminate_session(_session), do: :ok
  end

  defmodule FailingStatus do
    use GenServer

    def init(owner), do: {:ok, owner}

    def handle_call(:status, _from, owner) do
      monitor = Process.monitor(owner)
      Process.exit(owner, :kill)

      receive do
        {:DOWN, ^monitor, :process, ^owner, _reason} -> :ok
      end

      {:stop, :fixture_failure, owner}
    end
  end

  test "application serves the Echo agent through one local API" do
    assert {:ok, ["echo"]} = GenAgentServer.agents()
    assert {:ok, %{text: "echo: hello"}} = GenAgentServer.ask("echo", "hello")
    assert {:error, {:unknown_agent, "missing"}} = GenAgentServer.ask("missing", "hello")
  end

  test "status immediately after stopping an instance returns not found" do
    agents = [{"echo", GenAgentEnsemble.Agents.Simple, [backend: GenAgentEnsemble.Backends.Echo]}]
    prefix = "stopped-status-#{System.unique_integer([:positive])}"

    for first <- [:status, :agents], i <- 1..200 do
      name = "#{prefix}-#{first}-#{i}"
      assert {:ok, _pid} = GenAgentServer.start_instance(name, agents)
      assert :ok = GenAgentServer.stop_instance(name)

      case first do
        :status ->
          assert {:error, :instance_not_found} = GenAgentServer.status(name)
          assert {:error, :instance_not_found} = GenAgentServer.agents(name)

        :agents ->
          assert {:error, :instance_not_found} = GenAgentServer.agents(name)
          assert {:error, :instance_not_found} = GenAgentServer.status(name)
      end
    end
  end

  test "status preserves an unrelated Ensemble exit after the instance owner dies" do
    name = "failed-status-#{System.unique_integer([:positive])}"
    parent = self()

    owner =
      spawn(fn ->
        {:ok, _} = Registry.register(GenAgentServer.Registry, {:instance, name}, nil)
        send(parent, :instance_registered)

        receive do
          :keep_alive -> :ok
        end
      end)

    assert_receive :instance_registered

    assert {:ok, _pid} =
             GenServer.start(FailingStatus, owner,
               name: {:via, Registry, {GenAgentEnsemble.Registry, name}}
             )

    capture_log(fn ->
      assert {:fixture_failure, {GenServer, :call, _}} = catch_exit(GenAgentServer.status(name))
    end)
  end

  test "invocation results survive the caller and can be read repeatedly" do
    parent = self()

    spawn(fn ->
      send(parent, {:invocation, GenAgentServer.invoke("echo", "later")})
    end)

    assert_receive {:invocation, {:ok, id}}
    assert {:ok, :completed, response} = await_result(id)
    assert response.text == "echo: later"
    assert {:ok, :completed, ^response} = GenAgentServer.result(id)
    assert {:ok, :completed, ^response} = GenAgentServer.result(id)
  end

  test "instances isolate results and retain only the configured number" do
    name = "test-instance-#{System.unique_integer([:positive])}"

    agents = [
      {"echo", GenAgentEnsemble.Agents.Simple,
       [backend: GenAgentEnsemble.Backends.Echo, transform: &String.upcase/1]}
    ]

    assert {:ok, _pid} = GenAgentServer.start_instance(name, agents, max_results: 1)
    on_exit(fn -> GenAgentServer.stop_instance(name) end)

    assert {:ok, ["echo"]} = GenAgentServer.agents(name)
    assert {:ok, first} = GenAgentServer.invoke(name, "echo", "first")
    assert {:ok, :completed, %{text: "FIRST"}} = await_result(name, first)
    assert {:error, :not_found} = GenAgentServer.result(first)

    assert {:ok, second} = GenAgentServer.invoke(name, "echo", "second")
    assert {:ok, :completed, %{text: "SECOND"}} = await_result(name, second)
    assert {:error, :not_found} = GenAgentServer.result(name, first)
    assert {:ok, :completed, %{text: "SECOND"}} = GenAgentServer.result(name, second)
    assert :ok = GenAgentServer.stop_instance(name)
    assert {:error, :instance_not_found} = GenAgentServer.result(name, second)
  end

  test "a managed Pipeline uses one external route and retains its result" do
    name = "test-pipeline-#{System.unique_integer([:positive])}"
    simple = GenAgentEnsemble.Agents.Simple
    echo = GenAgentEnsemble.Backends.Echo
    stages = [{"draft", simple, [backend: echo]}, {"revise", simple, [backend: echo]}]

    assert {:ok, _pid} =
             GenAgentServer.start_pattern_instance(
               name,
               "pipeline",
               GenAgentEnsemble.Strategies.Pipeline,
               stages: stages
             )

    on_exit(fn -> GenAgentServer.stop_instance(name) end)

    assert {:ok, ["pipeline"]} = GenAgentServer.agents(name)
    assert {:ok, %{routes: ["pipeline"], agents: internal}} = GenAgentServer.status(name)
    assert Enum.sort(internal) == ["draft", "revise"]
    assert {:error, {:unknown_agent, "draft"}} = GenAgentServer.invoke(name, "draft", "task")

    assert {:ok, id} = GenAgentServer.CLI.run(["--instance", name, "invoke", "pipeline", "task"])
    assert {:ok, :completed, %{text: "echo: echo: task"}} = await_result(name, id)
    assert {:ok, "echo: echo: task"} = GenAgentServer.CLI.run(["--instance", name, "result", id])
  end

  test "a managed Supervisor fans out and returns through one invocation ID" do
    name = "test-supervisor-#{System.unique_integer([:positive])}"
    simple = GenAgentEnsemble.Agents.Simple
    echo = GenAgentEnsemble.Backends.Echo

    opts = [
      coordinator: {"coordinator", simple, [backend: echo]},
      worker_template: {"worker", simple, [backend: echo]},
      decomposer: fn _text -> ["first", "second"] end
    ]

    assert {:ok, _pid} =
             GenAgentServer.start_pattern_instance(
               name,
               "review",
               GenAgentEnsemble.Strategies.Supervisor,
               opts
             )

    on_exit(fn -> GenAgentServer.stop_instance(name) end)

    assert {:ok, id} = GenAgentServer.invoke(name, "review", "two parts")

    assert {:ok, :completed, %{text: "echo: first\n\necho: second"}} =
             await_result(name, id)

    assert {:ok, %{agents: ["coordinator"], routes: ["review"]}} = GenAgentServer.status(name)
  end

  test "in-flight admission is bounded and unknown agents are rejected" do
    name = "test-bounded-#{System.unique_integer([:positive])}"

    agents = [
      {"slow", GenAgentEnsemble.Agents.Simple,
       [backend: GenAgentEnsemble.Backends.Echo, delay_ms: 200]}
    ]

    assert {:ok, _pid} = GenAgentServer.start_instance(name, agents, max_in_flight: 1)
    on_exit(fn -> GenAgentServer.stop_instance(name) end)

    assert {:error, {:unknown_agent, "missing"}} =
             GenAgentServer.invoke(name, "missing", "hello")

    assert {:ok, id} = GenAgentServer.invoke(name, "slow", "one")
    assert {:error, :busy} = GenAgentServer.invoke(name, "slow", "two")
    assert {:ok, :completed, %{text: "echo: one"}} = await_result(name, id)
    assert {:ok, _id} = GenAgentServer.invoke(name, "slow", "two")
  end

  test "new admission collects a finished turn before applying the in-flight limit" do
    name = "test-admission-#{System.unique_integer([:positive])}"
    agents = [{"echo", GenAgentEnsemble.Agents.Simple, [backend: GenAgentEnsemble.Backends.Echo]}]

    assert {:ok, _pid} =
             GenAgentServer.start_instance(name, agents,
               max_in_flight: 1,
               poll_interval_ms: 1_000
             )

    on_exit(fn -> GenAgentServer.stop_instance(name) end)

    assert {:ok, first} = GenAgentServer.invoke(name, "echo", "one")
    await_ensemble_idle(name)
    assert {:ok, second} = GenAgentServer.invoke(name, "echo", "two")
    assert {:ok, :completed, %{text: "echo: one"}} = GenAgentServer.result(name, first)
    assert {:ok, :completed, %{text: "echo: two"}} = await_result(name, second)
  end

  test "failed turns are retained for repeatable reads" do
    name = "test-failure-#{System.unique_integer([:positive])}"

    agents = [{"broken", GenAgentEnsemble.Agents.Simple, [backend: ErrorBackend]}]

    assert {:ok, _pid} = GenAgentServer.start_instance(name, agents)
    on_exit(fn -> GenAgentServer.stop_instance(name) end)

    assert {:ok, id} = GenAgentServer.invoke(name, "broken", "hello")
    assert {:ok, :failed, reason} = await_result(name, id)
    assert reason == {:fixture_failure, %{}}
    assert {:ok, :failed, ^reason} = GenAgentServer.result(name, id)
  end

  test "CLI lists agents and routes an ask" do
    assert {:ok, instances} = GenAgentServer.CLI.run(["instances"])
    assert "server/default" in String.split(instances, "\n")
    assert capture_io(fn -> assert :ok = GenAgentServer.CLI.main(["agents"]) end) == "echo\n"

    assert capture_io(fn -> assert :ok = GenAgentServer.CLI.main(["ask", "echo", "hello"]) end) ==
             "echo: hello\n"

    assert {:ok, id} = GenAgentServer.CLI.run(["invoke", "echo", "from CLI"])
    assert {:ok, :completed, %{text: "echo: from CLI"}} = await_result(id)
    assert {:ok, "echo: from CLI"} = GenAgentServer.CLI.run(["result", id])
  end

  test "named profiles route CLI invocations and results independently" do
    name = "project-#{System.unique_integer([:positive])}"
    directory = Path.join(System.tmp_dir!(), name)
    File.mkdir_p!(directory)
    path = Path.join(directory, "profiles.json")
    File.write!(path, Jason.encode!(%{profiles: [%{name: name, cwd: ".", providers: ["echo"]}]}))

    on_exit(fn -> File.rm_rf!(directory) end)
    assert [{^name, agents}] = GenAgentServer.Profiles.load!(path)
    assert {:ok, _pid} = GenAgentServer.start_instance(name, agents)
    on_exit(fn -> GenAgentServer.stop_instance(name) end)

    assert name in GenAgentServer.instances()
    assert {:ok, "echo"} = GenAgentServer.CLI.run(["--instance", name, "agents"])
    assert {:ok, id} = GenAgentServer.CLI.run(["--instance", name, "invoke", "echo", "task"])
    assert {:ok, :completed, %{text: "echo: task"}} = await_result(name, id)
    assert {:ok, "echo: task"} = GenAgentServer.CLI.run(["--instance", name, "result", id])
    assert {:error, :not_found} = GenAgentServer.CLI.run(["result", id])
  end

  test "profile files reject duplicate names and missing project directories" do
    directory = Path.join(System.tmp_dir!(), "profiles-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    path = Path.join(directory, "profiles.json")
    on_exit(fn -> File.rm_rf!(directory) end)

    profile = %{name: "same", cwd: ".", providers: ["echo"]}
    File.write!(path, Jason.encode!(%{profiles: [profile, profile]}))

    assert_raise ArgumentError, ~r/duplicate profile names/, fn ->
      GenAgentServer.Profiles.load!(path)
    end

    File.write!(path, Jason.encode!(%{profiles: [%{profile | cwd: "missing"}]}))

    assert_raise ArgumentError, ~r/cwd is not a directory/, fn ->
      GenAgentServer.Profiles.load!(path)
    end
  end

  test "profile names cannot forge extra CLI instances with control characters" do
    directory = Path.join(System.tmp_dir!(), "profile-name-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    path = Path.join(directory, "profiles.json")
    on_exit(fn -> File.rm_rf!(directory) end)

    File.write!(
      path,
      Jason.encode!(%{profiles: [%{name: "real\nforged", cwd: ".", providers: ["echo"]}]})
    )

    assert_raise ArgumentError, ~r/control characters/, fn ->
      GenAgentServer.Profiles.load!(path)
    end
  end

  test "profiles require explicit provider-specific write modes" do
    directory = Path.join(System.tmp_dir!(), "modes-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    path = Path.join(directory, "profiles.json")
    on_exit(fn -> File.rm_rf!(directory) end)

    profile = %{
      name: "editing",
      cwd: ".",
      providers: ["claude", "codex"],
      claude_permission_mode: "accept_edits",
      codex_sandbox: "workspace_write"
    }

    File.write!(path, Jason.encode!(%{profiles: [profile]}))
    assert [{"editing", agents}] = GenAgentServer.Profiles.load!(path)
    assert {"claude", _, claude_opts} = Enum.find(agents, &(elem(&1, 0) == "claude"))
    assert {"codex", _, codex_opts} = Enum.find(agents, &(elem(&1, 0) == "codex"))
    assert claude_opts[:permission_mode] == :accept_edits
    assert codex_opts[:sandbox] == :workspace_write
    assert codex_opts[:approval_policy] == :never
    assert codex_opts[:ignore_user_config] == true

    File.write!(
      path,
      Jason.encode!(%{profiles: [Map.put(profile, :codex_user_config, "inherit")]})
    )

    assert [{"editing", inherited_agents}] = GenAgentServer.Profiles.load!(path)

    assert {"codex", _, inherited_opts} =
             Enum.find(inherited_agents, &(elem(&1, 0) == "codex"))

    refute Keyword.has_key?(inherited_opts, :ignore_user_config)

    File.write!(
      path,
      Jason.encode!(%{profiles: [Map.put(profile, :codex_user_config, "unknown")]})
    )

    assert_raise ArgumentError, ~r/invalid codex_user_config/, fn ->
      GenAgentServer.Profiles.load!(path)
    end

    File.write!(
      path,
      Jason.encode!(%{profiles: [%{profile | codex_sandbox: "danger_full_access"}]})
    )

    assert_raise ArgumentError, ~r/invalid codex_sandbox/, fn ->
      GenAgentServer.Profiles.load!(path)
    end

    File.write!(
      path,
      Jason.encode!(%{
        profiles: [
          %{name: "claude-only", cwd: ".", providers: ["claude"], codex_user_config: "inherit"}
        ]
      })
    )

    assert_raise ArgumentError, ~r/sets codex_user_config without codex/, fn ->
      GenAgentServer.Profiles.load!(path)
    end
  end

  test "one-shot Mix task rejects result commands that need a persistent release" do
    assert_raise Mix.Error, ~r/require a running server/, fn ->
      Mix.Tasks.GenAgentServer.run(["invoke", "echo", "hello"])
    end

    assert_raise Mix.Error, ~r/require a running server/, fn ->
      Mix.Tasks.GenAgentServer.run(["result", "inv-1"])
    end

    assert_raise Mix.Error, ~r/require a running server/, fn ->
      Mix.Tasks.GenAgentServer.run(["--instance", "project", "result", "inv-1"])
    end

    assert_raise Mix.Error, ~r/require a running server/, fn ->
      Mix.Tasks.GenAgentServer.run(["run-job", "probe"])
    end
  end

  test "remote command encodes quoted prompts as data" do
    prompt = ~S|What's "next"; #{GenAgentServer.stop()}|
    expression = GenAgentServer.Remote.expression(["ask", "echo", prompt])

    output = capture_io(fn -> Code.eval_string(expression) end)
    assert {:ok, "echo: " <> ^prompt} = GenAgentServer.Remote.decode_response(output)
  end

  test "remote command reports an inaccessible release executable" do
    previous = System.get_env("GEN_AGENT_SERVER_RELEASE_BIN")
    System.put_env("GEN_AGENT_SERVER_RELEASE_BIN", Path.expand("README.md"))

    try do
      assert_raise Mix.Error, ~r/server RPC could not start/, fn ->
        Mix.Tasks.GenAgentServer.Remote.run(["agents"])
      end
    after
      if previous do
        System.put_env("GEN_AGENT_SERVER_RELEASE_BIN", previous)
      else
        System.delete_env("GEN_AGENT_SERVER_RELEASE_BIN")
      end
    end
  end

  defp await_result(id), do: await_result(GenAgentServer.session_name(), id)

  defp await_ensemble_idle(name) do
    deadline = System.monotonic_time(:millisecond) + 2_000
    wait_ensemble_idle(name, deadline)
  end

  defp wait_ensemble_idle(name, deadline) do
    case GenAgentEnsemble.status(name) do
      {:ok, %{in_flight: 0}} ->
        :ok

      _ ->
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(10)
          wait_ensemble_idle(name, deadline)
        else
          flunk("timed out waiting for ensemble #{name}")
        end
    end
  end

  defp await_result(instance, id) do
    deadline = System.monotonic_time(:millisecond) + 2_000
    poll_result(instance, id, deadline)
  end

  defp poll_result(instance, id, deadline) do
    case GenAgentServer.result(instance, id) do
      {:ok, :pending} ->
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(10)
          poll_result(instance, id, deadline)
        else
          flunk("timed out waiting for invocation #{id}")
        end

      outcome ->
        outcome
    end
  end
end

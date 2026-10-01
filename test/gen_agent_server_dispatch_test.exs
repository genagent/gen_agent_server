defmodule GenAgentServerDispatchTest do
  use ExUnit.Case

  test "Quantum runs a configured Echo job and exposes its result ID" do
    directory = Path.join(System.tmp_dir!(), "dispatch-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    path = Path.join(directory, "server.json")

    File.write!(
      path,
      Jason.encode!(%{
        profiles: [],
        jobs: [
          %{
            name: "probe",
            instance: "server/default",
            agent: "echo",
            schedule: "@hourly",
            prompt: "scheduled"
          }
        ]
      })
    )

    old_path = Application.get_env(:gen_agent_server, :profile_file)
    old_agents = Application.fetch_env!(:gen_agent_server, :agents)
    assert :ok = Application.stop(:gen_agent_server)
    Application.put_env(:gen_agent_server, :profile_file, path)

    Application.put_env(:gen_agent_server, :agents, [
      {"echo", GenAgentEnsemble.Agents.Simple,
       [backend: GenAgentEnsemble.Backends.Echo, delay_ms: 500]}
    ])

    on_exit(fn ->
      Application.stop(:gen_agent_server)
      Application.put_env(:gen_agent_server, :profile_file, old_path)
      Application.put_env(:gen_agent_server, :agents, old_agents)
      Application.ensure_all_started(:gen_agent_server)
      File.rm_rf!(directory)
    end)

    assert {:ok, _apps} = Application.ensure_all_started(:gen_agent_server)
    assert ["probe"] = GenAgentServer.Dispatch.jobs()
    assert {:ok, nil} = GenAgentServer.Dispatch.latest("probe")
    assert :ok = GenAgentServer.Scheduler.run_job(:probe)

    id = wait_for_id("probe")
    assert {:error, :overlap} = GenAgentServer.Dispatch.run_job("probe")
    assert {:ok, :completed, %{text: "echo: scheduled"}} = wait_for_result(id)
    assert {:ok, ^id} = GenAgentServer.Dispatch.latest("probe")
    assert {:ok, ^id} = GenAgentServer.CLI.run(["job", "probe"])
  end

  test "job config rejects unknown agents and ambiguous prompts" do
    directory = Path.join(System.tmp_dir!(), "jobs-#{System.unique_integer([:positive])}")
    File.mkdir_p!(directory)
    path = Path.join(directory, "server.json")
    on_exit(fn -> File.rm_rf!(directory) end)

    job = %{
      name: "probe",
      instance: "server/default",
      agent: "missing",
      schedule: "@daily",
      prompt: "task"
    }

    File.write!(path, Jason.encode!(%{jobs: [job]}))

    assert_raise ArgumentError, ~r/unknown instance or agent/, fn ->
      GenAgentServer.Jobs.load!(path, %{"server/default" => ["echo"]})
    end

    File.write!(
      path,
      Jason.encode!(%{jobs: [job |> Map.put(:agent, "echo") |> Map.put(:prompt_file, "task.md")]})
    )

    assert_raise ArgumentError, ~r/exactly one/, fn ->
      GenAgentServer.Jobs.load!(path, %{"server/default" => ["echo"]})
    end
  end

  defp wait_for_id(name) do
    deadline = System.monotonic_time(:millisecond) + 2_000
    poll_id(name, deadline)
  end

  defp poll_id(name, deadline) do
    case GenAgentServer.Dispatch.latest(name) do
      {:ok, nil} ->
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(10)
          poll_id(name, deadline)
        else
          flunk("job did not submit")
        end

      {:ok, id} ->
        id
    end
  end

  defp wait_for_result(id) do
    deadline = System.monotonic_time(:millisecond) + 2_000
    poll_result(id, deadline)
  end

  defp poll_result(id, deadline) do
    case GenAgentServer.result(id) do
      {:ok, :pending} ->
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(10)
          poll_result(id, deadline)
        else
          flunk("job result did not complete")
        end

      result ->
        result
    end
  end
end

defmodule GenAgentServer.Schedule do
  @moduledoc """
  Optional calendar jobs from the server configuration file.

  An optional `GenAgentServer.Extension`. Listing it reads the `jobs` array of
  the file named by `:profile_file` (the same file that holds `profiles`),
  starts `GenAgentServer.Dispatch`, and starts the Quantum scheduler when at
  least one job is configured. It adds the `jobs` and `run_job` operations to
  `GenAgentServer.Ops` and the `jobs`, `job NAME`, and `run-job NAME` CLI
  commands. Jobs submit turns through the same bounded invocation API as manual
  requests, with telemetry source `:scheduler`.
  """

  @behaviour GenAgentServer.Extension

  alias GenAgentServer.{Dispatch, Jobs, Ops, Scheduler}
  import Ops, only: [op: 5, req: 3]

  @impl GenAgentServer.Extension
  def children(context) do
    jobs = Jobs.load!(context[:profile_file], context[:instances])

    quantum_jobs =
      Enum.map(jobs, fn job ->
        [
          name: job.name,
          schedule: job.schedule,
          overlap: job.overlap,
          run_strategy: Quantum.RunStrategy.Local,
          task: {Dispatch, :run_job, [job.name]}
        ]
      end)

    Application.put_env(:gen_agent_server, Scheduler, jobs: quantum_jobs)
    [{Dispatch, jobs}] ++ if(jobs == [], do: [], else: [Scheduler])
  end

  @impl GenAgentServer.Extension
  def operations do
    [
      op(
        "jobs",
        "List configured scheduled jobs with their latest invocation ID.",
        false,
        [],
        fn _ ->
          jobs =
            for name <- guarded_jobs() do
              {:ok, latest} = Dispatch.latest(name)
              %{name: name, latest: latest}
            end

          {:ok, %{jobs: jobs}}
        end
      ),
      op(
        "run_job",
        "Queue one immediate run of a scheduled job.",
        true,
        [req("name", :string, "Job name")],
        fn a ->
          with :ok <- run_job(a["name"]), do: {:ok, %{name: a["name"], queued: true}}
        end
      )
    ]
  end

  @impl GenAgentServer.Extension
  def cli(["jobs"], _source), do: {:ok, Enum.join(Dispatch.jobs(), "\n")}

  def cli(["job", name], _source) do
    case Dispatch.latest(name) do
      {:ok, nil} -> {:ok, "never run"}
      {:ok, id} -> {:ok, id}
      {:error, :unknown_job} -> {:error, {:message, "job #{name} not found"}}
      error -> error
    end
  end

  def cli(["run-job", name], _source) do
    case run_job(name) do
      :ok -> {:ok, "queued"}
      {:error, :unknown_job} -> {:error, {:message, "job #{name} not found"}}
    end
  end

  def cli(_args, _source), do: :unhandled

  @doc "Queue one immediate run of the configured job `name`."
  @spec run_job(String.t()) :: :ok | {:error, :unknown_job}
  def run_job(name) do
    if name in Dispatch.jobs() do
      Scheduler.run_job(String.to_existing_atom(name))
    else
      {:error, :unknown_job}
    end
  end

  defp guarded_jobs do
    Dispatch.jobs()
  catch
    :exit, {:noproc, _} -> []
  end
end

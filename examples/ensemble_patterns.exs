# Run with: mix run examples/ensemble_patterns.exs
# These sessions are managed by GenAgent Server. Each pattern has one external
# route even though Ensemble owns multiple internal agents.

defmodule ExampleResult do
  def await(instance, id, attempts \\ 100)

  def await(_instance, _id, 0), do: raise("timed out waiting for pattern result")

  def await(instance, id, attempts) do
    case GenAgentServer.result(instance, id) do
      {:ok, :pending} ->
        Process.sleep(20)
        await(instance, id, attempts - 1)

      result ->
        result
    end
  end
end

simple = GenAgentEnsemble.Agents.Simple
echo = GenAgentEnsemble.Backends.Echo
run_id = System.unique_integer([:positive])

pipeline_name = "example-pipeline-#{run_id}"

{:ok, _pid} =
  GenAgentServer.start_pattern_instance(
    pipeline_name,
    "pipeline",
    GenAgentEnsemble.Strategies.Pipeline,
    stages: [
      {"draft", simple, [backend: echo]},
      {"revise", simple, [backend: echo]}
    ]
  )

{:ok, pipeline_id} = GenAgentServer.invoke(pipeline_name, "pipeline", "a short note")
{:ok, :completed, pipeline_response} = ExampleResult.await(pipeline_name, pipeline_id)
"echo: echo: a short note" = pipeline_response.text
IO.puts("Pipeline: #{pipeline_response.text}")
:ok = GenAgentServer.stop_instance(pipeline_name)

supervisor_name = "example-supervisor-#{run_id}"

{:ok, _pid} =
  GenAgentServer.start_pattern_instance(
    supervisor_name,
    "supervisor",
    GenAgentEnsemble.Strategies.Supervisor,
    coordinator: {"coordinator", simple, [backend: echo]},
    worker_template: {"worker", simple, [backend: echo]},
    decomposer: fn text ->
      text
      |> String.replace_prefix("echo: ", "")
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
    end
  )

{:ok, supervisor_id} = GenAgentServer.invoke(supervisor_name, "supervisor", "first, second")
{:ok, :completed, supervisor_response} = ExampleResult.await(supervisor_name, supervisor_id)
"echo: first\n\necho: second" = supervisor_response.text
IO.puts("Supervisor:\n#{supervisor_response.text}")
:ok = GenAgentServer.stop_instance(supervisor_name)

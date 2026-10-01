# Run with: mix run examples/ensemble_patterns.exs
# These sessions use Ensemble directly inside the same OTP application.
# GenAgent Server does not yet route invocation IDs to pattern sessions.

simple = GenAgentEnsemble.Agents.Simple
echo = GenAgentEnsemble.Backends.Echo
run_id = System.unique_integer([:positive])

pipeline_name = "example-pipeline-#{run_id}"

{:ok, _pid} =
  GenAgentEnsemble.start_link(
    name: pipeline_name,
    strategy: GenAgentEnsemble.Strategies.Pipeline,
    opts: [
      stages: [
        {"draft", simple, [backend: echo]},
        {"revise", simple, [backend: echo]}
      ]
    ]
  )

{:ok, pipeline_response} = GenAgentEnsemble.ask(pipeline_name, "a short note")
"echo: echo: a short note" = pipeline_response.text
IO.puts("Pipeline: #{pipeline_response.text}")
:ok = GenAgentEnsemble.stop(pipeline_name)

supervisor_name = "example-supervisor-#{run_id}"

{:ok, _pid} =
  GenAgentEnsemble.start_link(
    name: supervisor_name,
    strategy: GenAgentEnsemble.Strategies.Supervisor,
    opts: [
      coordinator: {"coordinator", simple, [backend: echo]},
      worker_template: {"worker", simple, [backend: echo]},
      decomposer: fn text ->
        text
        |> String.replace_prefix("echo: ", "")
        |> String.split(",", trim: true)
        |> Enum.map(&String.trim/1)
      end
    ]
  )

{:ok, supervisor_response} = GenAgentEnsemble.ask(supervisor_name, "first, second")
"echo: first\n\necho: second" = supervisor_response.text
IO.puts("Supervisor:\n#{supervisor_response.text}")
:ok = GenAgentEnsemble.stop(supervisor_name)

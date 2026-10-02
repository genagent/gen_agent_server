{:ok, _pid} = GenAgentEnsemble.start_link(
  name: "research-1",
  strategy: GenAgentEnsemble.Strategies.Solo,
  opts: [
    agent:
      {"worker-a", GenAgentEnsemble.Agents.Simple,
       backend: GenAgentEnsemble.Backends.Echo}
  ]
)

{:ok, token} = GenAgentEnsemble.tell("research-1", "hello")
{:ok, response} = GenAgentEnsemble.await("research-1", token)
{:ok, :completed, ^response} = GenAgentEnsemble.poll("research-1", token)
{:ok, %{text: "echo: quick question"}} =
  GenAgentEnsemble.ask("research-1", "quick question", timeout: 30_000)

:ok = GenAgentEnsemble.stop("research-1")
IO.puts("copyable Ensemble example passed")

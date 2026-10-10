# Run: mix run examples/control_ledger_echo.exs
# No provider login. Caller starts everything, owns admission and receives raw
# notifications directly; the ledger never invokes or consumes an Ensemble inbox.
alias GenAgentServer.Control.Ledger

{:ok, ledger} = Ledger.start_link()
instance = "ledger-echo-#{System.unique_integer([:positive])}"
names = ["alpha", "beta"]
checkout = File.cwd!()

agents =
  Enum.map(names, fn name ->
    {name, GenAgentEnsemble.Agents.Simple,
     [backend: GenAgentEnsemble.Backends.Echo, delay_ms: 10]}
  end)

{:ok, _} = GenAgentServer.start_instance(instance, agents, max_in_flight: 2, max_results: 1)

try do
  {:ok, run} =
    Ledger.open(ledger, %{
      name: "Echo evidence",
      control_revision: "example-v1",
      tasks: Enum.map(names, &%{name: &1, checkout: checkout, required_checks: []})
    })

  # Separate named raw agents allow overlapping work. The caller chooses how much
  # to admit; ledger limits bound retained data, never worker concurrency.
  pending =
    Map.new(names, fn name ->
      prompt = "hello #{name}"

      spec = %{
        stage: "draft",
        kind: :work,
        provider: "echo",
        requested_settings: %{},
        instruction_revision: "example-v1",
        checkout: checkout,
        prompt: prompt
      }

      {:ok, attempt} = Ledger.record_attempt(ledger, run, name, spec)
      {:ok, invocation} = GenAgentServer.invoke(instance, name, prompt, recipient: self())
      {invocation, attempt}
    end)

  Enum.each(1..map_size(pending), fn _ ->
    receive do
      {:gen_agent_server, :completion, %{instance: ^instance, invocation_id: invocation},
       {:ok, :completed, %{text: text}}} ->
        # Ingest only selected fields; do not pass Response.events or metadata.
        :ok =
          Ledger.finish_attempt(ledger, run, Map.fetch!(pending, invocation), %{
            status: :completed,
            text: text,
            invocation_id: invocation
          })
    after
      5_000 -> raise "caller timed out waiting for Echo; cleanup remains caller-owned"
    end
  end)

  {:ok, snapshot} = Ledger.result(ledger, run)
  {:ok, ^snapshot} = Ledger.result(ledger, run)
  raw = Enum.map(Map.keys(pending), &GenAgentServer.result(instance, &1))
  true = Enum.count(raw, &(&1 == {:error, :not_found})) == 1
  true = Enum.all?(snapshot.attempts, fn {_, a} -> a.terminal.text == "echo: hello #{a.task}" end)
  IO.puts("Both named attempts retained; repeat read identical; one raw result evicted.")
  IO.inspect(snapshot.attempts, label: "Caller-recorded evidence")
  :ok = Ledger.close(ledger, run)
  # Keep until caller chooses to forget or stops the ledger. No acceptance,
  # verification or publication is manufactured from successful Echo output.
after
  GenAgentServer.stop_instance(instance)
  GenServer.stop(ledger)
end

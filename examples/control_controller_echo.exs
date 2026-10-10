# Run: mix run examples/control_controller_echo.exs
# Login-free first #40 increment, not real workflow-batch acceptance.
alias GenAgentServer.Control.{Controller, Ledger}

instance = "controller-echo-#{System.unique_integer([:positive])}"
names = ["alpha", "beta"]

{:ok, _} =
  GenAgentServer.create_instance(instance, %{
    "cwd" => File.cwd!(),
    "max_in_flight" => 2,
    "max_results" => 1,
    "routes" => Enum.map(names, &%{"name" => &1, "provider" => "echo"})
  })

{:ok, ledger} = Ledger.start_link()

{:ok, run} =
  Ledger.open(ledger, %{
    name: "independent Echo tasks",
    control_revision: "example-v1",
    tasks: Enum.map(names, &%{name: &1, checkout: File.cwd!(), required_checks: []})
  })

{:ok, controller} = Controller.start_link(instance: instance, ledger: ledger, run: run)

try do
  ids =
    Enum.map(names, fn task ->
      spec = %{
        stage: "work",
        kind: :work,
        provider: "echo",
        requested_settings: %{},
        instruction_revision: "example-v1",
        checkout: File.cwd!(),
        prompt: "hello #{task}"
      }

      {:ok, id} = Controller.submit(controller, task, task, spec)
      {:ok, ^id} = Controller.submit(controller, task, task, spec)
      id
    end)

  # Waiting is caller policy. Expiry never requests cancellation or proves cleanup.
  wait = fn wait, remaining ->
    {:ok, snapshot} = Controller.result(controller)

    cond do
      Enum.all?(ids, &(snapshot.attempts[&1].terminal != nil)) ->
        snapshot

      remaining == 0 ->
        raise "Echo wait expired; inspect controller evidence"

      true ->
        Process.sleep(10)
        wait.(wait, remaining - 1)
    end
  end

  snapshot = wait.(wait, 500)
  {:ok, ^snapshot} = Controller.result(controller)
  raw = Enum.map(ids, &GenAgentServer.result(instance, snapshot.attempts[&1].invocation_id))
  true = Enum.count(raw, &(&1 == {:error, :not_found})) == 1
  {:ok, evidence} = Ledger.result(ledger, run)
  true = evidence.reserved_bytes == 0
  IO.inspect(snapshot, label: "Repeatable controller evidence after raw eviction")
after
  GenServer.stop(controller)
  # These are caller-owned resources. Controller shutdown never stops them.
  GenAgentServer.stop_instance(instance)
  GenServer.stop(ledger)
end

# Run: mix run examples/control_controller_echo.exs
# Login-free explicit work/review stages, not real mixed-provider issue-batch acceptance.
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
    tasks: Enum.map(names, &%{name: &1, checkout: File.cwd!(), required_checks: ["smoke"]})
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
  wait = fn wait, pending, remaining ->
    {:ok, snapshot} = Controller.result(controller)

    cond do
      Enum.all?(pending, &(snapshot.attempts[&1].terminal != nil)) ->
        snapshot

      remaining == 0 ->
        raise "Echo wait expired; inspect controller evidence"

      true ->
        Process.sleep(10)
        wait.(wait, pending, remaining - 1)
    end
  end

  snapshot = wait.(wait, ids, 500)
  {:ok, ^snapshot} = Controller.result(controller)
  raw = Enum.map(ids, &GenAgentServer.result(instance, snapshot.attempts[&1].invocation_id))
  true = Enum.count(raw, &(&1 == {:error, :not_found})) == 1
  {:ok, evidence} = Ledger.result(ledger, run)
  true = evidence.reserved_bytes == 0
  # The caller fingerprints this example's output, then records its revision.
  # Real work should fingerprint the actual checkout/artifact being reviewed.
  reviews =
    Enum.zip(names, ids)
    |> Enum.map(fn {task, work} ->
      fingerprint =
        :crypto.hash(:sha256, snapshot.attempts[work].terminal.text)
        |> Base.encode16(case: :lower)

      {:ok, revision} =
        Ledger.record_revision(ledger, run, %{
          task: task,
          produced_by_attempt_id: work,
          content_sha256: fingerprint,
          recorded_by: "example caller"
        })

      review_spec = %{
        stage: "review-1",
        kind: :review,
        subject_revision_id: revision,
        provider: "echo",
        requested_settings: %{},
        instruction_revision: "example-v1",
        checkout: File.cwd!(),
        prompt: "Review recorded Echo revision #{revision}"
      }

      {:ok, review} = Controller.submit(controller, task, task, review_spec)
      {:ok, ^review} = Controller.submit(controller, task, task, review_spec)
      {revision, review}
    end)

  reviewed = wait.(wait, Enum.map(reviews, &elem(&1, 1)), 500)

  Enum.each(reviews, fn {revision, review} ->
    ^revision = reviewed.attempts[review].subject_revision_id
    :review = reviewed.attempts[review].kind
    # An explicit caller decision for this synthetic example, never parsed from text.
    # Echo is not an independent code review and establishes no real batch acceptance.
    {:ok, _} =
      Ledger.record_review(ledger, run, %{
        revision_id: revision,
        review_attempt_id: review,
        verdict: :approve,
        recorded_by: "example caller"
      })

    {output, exit_status} = System.cmd("sh", ["-c", "exit 0"], cd: File.cwd!())

    {:ok, _} =
      Ledger.record_verification(ledger, run, %{
        revision_id: revision,
        check_name: "smoke",
        cwd: File.cwd!(),
        argv: ["sh", "-c", "exit 0"],
        exit_status: exit_status,
        outcome: if(exit_status == 0, do: :passed, else: :failed),
        output: output,
        recorded_by: "example caller"
      })

    {:ok, _} =
      Ledger.record_acceptance(ledger, run, %{
        revision_id: revision,
        decision: :accepted,
        recorded_by: "example host"
      })
  end)

  {:ok, summary} = Ledger.status(ledger, run)
  IO.inspect(reviewed, label: "Repeatable work/review evidence")
  IO.inspect(summary, label: "Separate caller-recorded gates (synthetic Echo example)")
  # #40 remains open: two actual mixed-provider issue-batch acceptances remain.
after
  GenServer.stop(controller)
  # These are caller-owned resources. Controller shutdown never stops them.
  GenAgentServer.stop_instance(instance)
  GenServer.stop(ledger)
end

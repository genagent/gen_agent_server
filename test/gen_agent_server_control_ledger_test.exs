defmodule GenAgentServer.Control.LedgerTest do
  use ExUnit.Case, async: true
  alias GenAgentServer.Control.Ledger

  defp manifest(tasks \\ ["alpha"]) do
    %{
      name: "run",
      control_revision: "instructions-v1",
      tasks: Enum.map(tasks, &%{name: &1, checkout: "/work/" <> &1, required_checks: ["test"]})
    }
  end

  defp spec(task \\ "alpha", changes \\ %{}) do
    Map.merge(
      %{
        stage: "implement",
        kind: :work,
        provider: "echo",
        requested_settings: %{"model" => "requested", "effort" => "low"},
        instruction_revision: "v1",
        checkout: "/work/" <> task,
        prompt: "hello"
      },
      changes
    )
  end

  defp ledger(limits \\ []) do
    start_supervised!({Ledger, limits: limits})
  end

  defp open(l, tasks \\ ["alpha"]) do
    assert {:ok, id} = Ledger.open(l, manifest(tasks))
    id
  end

  defp completed(l, run, task \\ "alpha", changes \\ %{}) do
    assert {:ok, id} = Ledger.record_attempt(l, run, task, spec(task, changes))
    assert :ok = Ledger.finish_attempt(l, run, id, %{status: :completed, text: "done"})
    id
  end

  defp revision(l, run, attempt, task \\ "alpha", fingerprint \\ String.duplicate("a", 64)) do
    assert {:ok, id} =
             Ledger.record_revision(l, run, %{
               task: task,
               produced_by_attempt_id: attempt,
               content_sha256: fingerprint,
               recorded_by: "caller"
             })

    id
  end

  defp approve(l, run, revision, task \\ "alpha") do
    attempt =
      completed(l, run, task, %{stage: "review", kind: :review, subject_revision_id: revision})

    assert {:ok, id} =
             Ledger.record_review(l, run, %{
               review_attempt_id: attempt,
               revision_id: revision,
               verdict: :approve,
               recorded_by: "caller"
             })

    id
  end

  defp verify(l, run, revision, outcome \\ :passed, exit_status \\ 0) do
    Ledger.record_verification(l, run, %{
      revision_id: revision,
      check_name: "test",
      argv: ["mix", "test", ""],
      cwd: "/work/alpha",
      exit_status: exit_status,
      outcome: outcome,
      recorded_by: "caller",
      output: "actual caller output"
    })
  end

  defp accept(l, run, revision) do
    Ledger.record_acceptance(l, run, %{
      revision_id: revision,
      decision: :accepted,
      recorded_by: "host"
    })
  end

  test "multiple attempts append immutable specifications, once-only evidence and repeatable history" do
    l = ledger()
    run = open(l, ["alpha", "beta"])
    assert {:ok, first} = Ledger.record_attempt(l, run, "alpha", spec())

    second_spec =
      spec("alpha", %{
        instruction_revision: "v2",
        prompt: "revised",
        requested_settings: %{"model" => "different"}
      })

    assert {:ok, second} = Ledger.record_attempt(l, run, "alpha", second_spec)
    third = completed(l, run, "beta")
    refute first == second

    assert :ok =
             Ledger.finish_attempt(l, run, second, %{status: :failed, failure: "caller observed"})

    assert :ok = Ledger.finish_attempt(l, run, first, %{status: :completed, text: ""})
    assert {:ok, snapshot} = Ledger.result(l, run)
    assert map_size(snapshot.attempts) == 3
    assert snapshot.attempts[first].spec == spec()
    assert snapshot.attempts[second].spec == second_spec
    assert snapshot.attempts[first].terminal.text == ""
    assert snapshot.attempts[first].terminal.actual_model == nil
    assert snapshot.attempts[second].terminal.text == nil
    assert snapshot.attempts[third].task == "beta"
    assert :ok = Ledger.finish_attempt(l, run, first, %{status: :completed, text: ""})

    assert {:error, :conflict} =
             Ledger.finish_attempt(l, run, first, %{status: :completed, text: "changed"})

    for _ <- 1..3, do: assert(Ledger.result(l, run) == {:ok, snapshot})
  end

  test "only explicit actual model is retained; arbitrary events and metadata rejected" do
    l = ledger()
    run = open(l)
    assert {:ok, id} = Ledger.record_attempt(l, run, "alpha", spec())

    for payload <- [
          %{status: :completed, events: []},
          %{status: :completed, metadata: %{model: "x"}},
          %{"text" => "bad", status: :completed},
          %{status: :completed, failure: {:error, :opaque}}
        ] do
      assert {:error, :invalid_record} = Ledger.finish_attempt(l, run, id, payload)
    end

    assert {:error, :invalid_record} =
             Ledger.record_attempt(
               l,
               run,
               "alpha",
               spec("alpha", %{requested_settings: %{"nested" => %{}}})
             )

    assert :ok =
             Ledger.finish_attempt(l, run, id, %{status: :completed, actual_model: "observed"})

    assert {:ok, snapshot} = Ledger.result(l, run)
    assert snapshot.attempts[id].terminal.actual_model == "observed"
  end

  test "missing references and cross-run references cannot bind records" do
    l = ledger()
    one = open(l, ["alpha", "beta"])
    two = open(l)
    attempt = completed(l, one)
    rev = revision(l, one, attempt)
    assert {:error, :not_found} = Ledger.finish_attempt(l, two, attempt, %{status: :completed})

    assert {:error, :not_found} =
             Ledger.record_attempt(
               l,
               two,
               "alpha",
               spec("alpha", %{kind: :review, subject_revision_id: rev})
             )

    assert {:error, :invalid_subject} =
             Ledger.record_attempt(
               l,
               one,
               "beta",
               spec("beta", %{kind: :review, subject_revision_id: rev})
             )

    assert {:error, :not_found} = Ledger.record_attempt(l, one, "missing", spec())
    assert {:error, :checkout_mismatch} = Ledger.record_attempt(l, one, "alpha", spec("beta"))
    assert {:error, :not_found} = accept(l, two, rev)

    assert {:error, :not_found} =
             Ledger.record_revision(l, two, %{
               task: "alpha",
               produced_by_attempt_id: attempt,
               content_sha256: String.duplicate("a", 64),
               recorded_by: "caller"
             })
  end

  test "review needs completed review-kind attempt for exactly the subject revision" do
    l = ledger()
    run = open(l)
    work = completed(l, run)
    r1 = revision(l, run, work)
    r2 = revision(l, run, work, "alpha", String.duplicate("b", 64))
    record = %{review_attempt_id: work, revision_id: r1, verdict: :approve, recorded_by: "caller"}
    assert {:error, :invalid_review} = Ledger.record_review(l, run, record)

    assert {:ok, pending} =
             Ledger.record_attempt(
               l,
               run,
               "alpha",
               spec("alpha", %{kind: :review, subject_revision_id: r1})
             )

    assert {:error, :invalid_review} =
             Ledger.record_review(l, run, %{record | review_attempt_id: pending})

    assert :ok = Ledger.finish_attempt(l, run, pending, %{status: :failed})

    assert {:error, :invalid_review} =
             Ledger.record_review(l, run, %{record | review_attempt_id: pending})

    review = completed(l, run, "alpha", %{kind: :review, subject_revision_id: r1})

    assert {:error, :invalid_review} =
             Ledger.record_review(l, run, %{record | review_attempt_id: review, revision_id: r2})

    assert {:ok, _} = Ledger.record_review(l, run, %{record | review_attempt_id: review})
  end

  test "approval then exit 1 blocks acceptance; latest failure cannot be bypassed" do
    l = ledger()
    run = open(l)
    rev = revision(l, run, completed(l, run))
    assert {:error, :missing_approval} = accept(l, run, rev)
    review = approve(l, run, rev)
    assert {:error, :checks_not_passed} = accept(l, run, rev)
    assert {:error, :invalid_pass} = verify(l, run, rev, :passed, 1)
    assert {:ok, _failure} = verify(l, run, rev, :failed, 1)
    assert {:error, :checks_not_passed} = accept(l, run, rev)
    assert {:ok, pass} = verify(l, run, rev)
    assert {:ok, acceptance} = accept(l, run, rev)
    assert {:ok, before} = Ledger.result(l, run)
    accepted = Enum.find(before.records, &(&1.id == acceptance))
    assert accepted.review_ids == [review]
    assert accepted.verification_ids == [pass]
    assert {:ok, %{tasks: %{"alpha" => %{accepted: true}}}} = Ledger.status(l, run)
    assert {:ok, _} = verify(l, run, rev, :failed, 1)
    assert {:error, :checks_not_passed} = accept(l, run, rev)
    assert {:ok, %{tasks: %{"alpha" => %{accepted: false}}}} = Ledger.status(l, run)
    assert {:ok, after_failure} = Ledger.result(l, run)
    assert Enum.find(after_failure.records, &(&1.id == acceptance)) == accepted

    assert {:error, :invalid_record} =
             Ledger.record_acceptance(l, run, %{
               revision_id: rev,
               decision: :accepted,
               recorded_by: "host",
               verification_ids: [pass]
             })
  end

  test "missing, not-run, timed-out and later non-approving review block gates" do
    l = ledger()
    run = open(l)
    rev = revision(l, run, completed(l, run))
    approve(l, run, rev)

    for outcome <- [:not_run, :timed_out] do
      assert {:ok, _} = verify(l, run, rev, outcome, nil)
      assert {:error, :checks_not_passed} = accept(l, run, rev)
    end

    assert {:ok, _} = verify(l, run, rev)
    review = completed(l, run, "alpha", %{kind: :review, subject_revision_id: rev})

    assert {:ok, _} =
             Ledger.record_review(l, run, %{
               revision_id: rev,
               review_attempt_id: review,
               verdict: :changes_requested,
               recorded_by: "caller"
             })

    assert {:error, :missing_approval} = accept(l, run, rev)
  end

  test "new current revision inherits no gates and historical evidence stays intact" do
    l = ledger()
    run = open(l)
    work = completed(l, run)
    old = revision(l, run, work)
    approve(l, run, old)
    assert {:ok, _} = verify(l, run, old)
    assert {:ok, accepted} = accept(l, run, old)
    assert {:ok, before} = Ledger.result(l, run)
    new = revision(l, run, work, "alpha", String.duplicate("b", 64))
    assert {:error, :stale_revision} = accept(l, run, old)
    assert {:error, :missing_approval} = accept(l, run, new)
    approve(l, run, new)
    assert {:error, :checks_not_passed} = accept(l, run, new)
    assert {:ok, snapshot} = Ledger.result(l, run)
    assert Enum.take(snapshot.records, length(before.records)) == before.records
    assert Enum.any?(snapshot.records, &(&1.id == accepted))

    assert {:ok, %{tasks: %{"alpha" => %{current_revision_id: ^new, accepted: false}}}} =
             Ledger.status(l, run)
  end

  test "unfinished attempt blocks acceptance; close admits only terminal completion and forget requires settled storage" do
    l = ledger()
    run = open(l)
    rev = revision(l, run, completed(l, run))
    approve(l, run, rev)
    assert {:ok, _} = verify(l, run, rev)
    assert {:ok, unfinished} = Ledger.record_attempt(l, run, "alpha", spec())
    assert {:error, :unfinished_attempts} = accept(l, run, rev)
    assert {:error, :not_closed} = Ledger.forget(l, run)
    assert :ok = Ledger.close(l, run)
    assert {:error, :unfinished_attempts} = Ledger.forget(l, run)
    assert {:error, :closed} = Ledger.record_attempt(l, run, "alpha", spec())
    assert {:error, :closed} = verify(l, run, rev)

    assert :ok =
             Ledger.finish_attempt(l, run, unfinished, %{
               status: :cancelled,
               failure: "caller attests"
             })

    assert :ok = Ledger.close(l, run)
    assert :ok = Ledger.forget(l, run)
    assert {:error, :not_found} = Ledger.result(l, run)
  end

  test "finite run/task/attempt quotas and forget frees run capacity" do
    l = ledger(runs: 1, tasks_per_run: 1, attempts_per_run: 1)
    assert {:error, :quota_exhausted} = Ledger.open(l, manifest(["alpha", "beta"]))
    run = open(l)
    assert {:error, :quota_exhausted} = Ledger.open(l, manifest())
    id = completed(l, run)
    assert {:error, :quota_exhausted} = Ledger.record_attempt(l, run, "alpha", spec())
    assert {:ok, snapshot} = Ledger.result(l, run)
    assert snapshot.attempts[id].terminal.text == "done"
    assert :ok = Ledger.close(l, run)
    assert :ok = Ledger.forget(l, run)
    assert {:ok, _} = Ledger.open(l, manifest())
  end

  test "record exhaustion rejects admission and preserves reserved terminal slots" do
    l = ledger(records_per_run: 3)
    run = open(l)
    assert {:ok, id} = Ledger.record_attempt(l, run, "alpha", spec())
    assert {:ok, before} = Ledger.result(l, run)

    assert {:error, :quota_exhausted} =
             Ledger.record_attempt(l, run, "alpha", spec())

    assert {:ok, ^before} = Ledger.result(l, run)
    assert before.attempts[id].terminal == nil
    assert :ok = Ledger.close(l, run)
    assert {:error, :unfinished_attempts} = Ledger.forget(l, run)
    assert :ok = Ledger.finish_attempt(l, run, id, %{status: :completed, text: ""})
    assert {:ok, after_finish} = Ledger.result(l, run)
    assert after_finish.record_count == before.record_count
    assert :ok = Ledger.forget(l, run)
  end

  test "per-record byte quota rejects finish atomically; bounded retry works" do
    l = ledger(record_bytes: 1024)
    run = open(l)
    assert {:ok, id} = Ledger.record_attempt(l, run, "alpha", spec())
    assert {:ok, before} = Ledger.result(l, run)
    # The text fits its field limit but the full terminal envelope does not.
    assert {:error, :quota_exhausted} =
             Ledger.finish_attempt(l, run, id, %{
               status: :completed,
               text: String.duplicate("x", 1024)
             })

    assert {:ok, ^before} = Ledger.result(l, run)

    assert :ok =
             Ledger.finish_attempt(l, run, id, %{
               status: :completed,
               text: "bounded",
               artifact_refs: ["/external/full-output"]
             })
  end

  test "overall byte budget spans runs and forget frees charged bytes" do
    l = ledger(total_bytes: 1100)
    run = open(l)
    id = completed(l, run)
    assert {:ok, before} = Ledger.result(l, run)
    assert before.bytes < 1100

    assert {:error, :quota_exhausted} =
             Ledger.record_attempt(
               l,
               run,
               "alpha",
               spec("alpha", %{prompt: String.duplicate("x", 600)})
             )

    assert {:ok, ^before} = Ledger.result(l, run)
    # Manifest quota is shared with the first run's retained evidence.
    assert {:error, :quota_exhausted} =
             Ledger.open(l, %{manifest() | name: String.duplicate("x", 600)})

    assert before.attempts[id].terminal != nil
    assert :ok = Ledger.close(l, run)
    assert :ok = Ledger.forget(l, run)
    assert {:ok, _} = Ledger.open(l, %{manifest() | name: String.duplicate("x", 600)})
  end

  test "limits reject infinity, zero, unknown and values above hard ceiling" do
    for limits <- [[runs: :infinity], [total_bytes: 0], [runs: 5], [workers: 1], :infinity] do
      Process.flag(:trap_exit, true)
      assert {:error, :invalid_limits} = Ledger.start_link(limits: limits)
    end
  end

  test "strict manifests, fingerprints and prompt references" do
    l = ledger()
    assert {:error, :duplicate_task} = Ledger.open(l, manifest(["alpha", "alpha"]))

    assert {:error, :invalid_record} =
             Ledger.open(l, %{
               manifest()
               | tasks: [%{name: "alpha", checkout: "relative", required_checks: []}]
             })

    run = open(l)

    assert {:error, :invalid_prompt} =
             Ledger.record_attempt(l, run, "alpha", spec("alpha", %{prompt_ref: "artifact"}))

    ref_spec = spec() |> Map.delete(:prompt) |> Map.put(:prompt_ref, "artifact:sha256:caller")
    assert {:ok, id} = Ledger.record_attempt(l, run, "alpha", ref_spec)
    assert :ok = Ledger.finish_attempt(l, run, id, %{status: :completed})

    assert {:error, :invalid_record} =
             Ledger.record_revision(l, run, %{
               task: "alpha",
               produced_by_attempt_id: id,
               content_sha256: "HEAD",
               recorded_by: "caller"
             })

    assert {:error, :invalid_record} =
             Ledger.record_attempt(
               l,
               run,
               "alpha",
               spec("alpha", %{requested_settings: %{"huge" => String.duplicate("x", 4097)}})
             )
  end

  test "API caller death preserves evidence and process restart cannot recover old IDs" do
    l = ledger()
    parent = self()

    {pid, ref} =
      spawn_monitor(fn ->
        run = open(l)
        attempt = completed(l, run)
        send(parent, {:stored, run, attempt})
      end)

    assert_receive {:stored, run, attempt}
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    assert {:ok, snapshot} = Ledger.result(l, run)
    assert snapshot.attempts[attempt].terminal.text == "done"
    assert Ledger.child_spec([]).restart == :temporary
    assert :ok = stop_supervised(Ledger)
    replacement = ledger()
    assert {:error, :not_found} = Ledger.result(replacement, run)
    new = open(replacement)
    refute run == new

    assert {:error, :not_found} =
             Ledger.finish_attempt(replacement, new, attempt, %{status: :completed})
  end

  test "all required checks need current passing records with caller argv/cwd" do
    l = ledger()

    m = %{
      manifest()
      | tasks: [%{name: "alpha", checkout: "/work/alpha", required_checks: ["test", "format"]}]
    }

    assert {:ok, run} = Ledger.open(l, m)
    rev = revision(l, run, completed(l, run))
    approve(l, run, rev)
    assert {:ok, check} = verify(l, run, rev)
    assert {:error, :checks_not_passed} = accept(l, run, rev)

    format = %{
      revision_id: rev,
      check_name: "format",
      argv: ["mix", "format", "--check-formatted"],
      cwd: "/wrong",
      exit_status: 0,
      outcome: :passed,
      recorded_by: "caller"
    }

    assert {:error, :checkout_mismatch} = Ledger.record_verification(l, run, format)
    assert {:ok, _} = Ledger.record_verification(l, run, %{format | cwd: "/work/alpha"})
    assert {:ok, _} = accept(l, run, rev)
    assert {:ok, snapshot} = Ledger.result(l, run)
    recorded = Enum.find(snapshot.records, &(&1.id == check))
    assert recorded.data.argv == ["mix", "test", ""]
    assert recorded.data.cwd == "/work/alpha"
    assert recorded.data.exit_status == 0
    assert recorded.data.outcome == :passed
  end

  test "revision producer must be completed work in that task" do
    l = ledger()
    run = open(l, ["alpha", "beta"])
    assert {:ok, attempt} = Ledger.record_attempt(l, run, "alpha", spec())

    data = %{
      task: "alpha",
      produced_by_attempt_id: attempt,
      content_sha256: String.duplicate("a", 64),
      recorded_by: "caller"
    }

    assert {:error, :invalid_producer} = Ledger.record_revision(l, run, data)
    assert :ok = Ledger.finish_attempt(l, run, attempt, %{status: :failed})
    assert {:error, :invalid_producer} = Ledger.record_revision(l, run, data)
    work = completed(l, run)

    assert {:error, :invalid_producer} =
             Ledger.record_revision(l, run, %{data | task: "beta", produced_by_attempt_id: work})

    assert {:ok, rev} = Ledger.record_revision(l, run, %{data | produced_by_attempt_id: work})
    review = completed(l, run, "alpha", %{kind: :review, subject_revision_id: rev})

    assert {:error, :invalid_producer} =
             Ledger.record_revision(l, run, %{data | produced_by_attempt_id: review})
  end

  test "malformed lists reject every call without changing retained evidence" do
    l = ledger()
    run = open(l)
    work = completed(l, run)
    rev = revision(l, run, work)
    approve(l, run, rev)
    assert {:ok, _} = verify(l, run, rev)
    assert {:ok, _} = accept(l, run, rev)
    assert {:ok, pending} = Ledger.record_attempt(l, run, "alpha", spec())
    assert {:ok, before} = Ledger.result(l, run)
    assert {:ok, status_before} = Ledger.status(l, run)
    task = hd(manifest().tasks)

    revision_data = %{
      task: "alpha",
      produced_by_attempt_id: work,
      content_sha256: String.duplicate("a", 64),
      recorded_by: "caller"
    }

    verification = %{
      revision_id: rev,
      check_name: "test",
      argv: ["mix", "test"],
      cwd: "/work/alpha",
      exit_status: 0,
      outcome: :passed,
      recorded_by: "caller"
    }

    calls =
      for bad <- [
            :not_list,
            ["ref" | :tail],
            ["ref" | "tail"],
            ["ref", "ref" | %{tail: true}],
            List.duplicate("ref", 33)
          ],
          call <- [
            fn -> Ledger.open(l, %{manifest() | tasks: [%{task | required_checks: bad}]}) end,
            fn ->
              Ledger.finish_attempt(l, run, pending, %{status: :completed, artifact_refs: bad})
            end,
            fn -> Ledger.record_revision(l, run, Map.put(revision_data, :artifact_refs, bad)) end,
            fn -> Ledger.record_verification(l, run, %{verification | argv: bad}) end,
            fn ->
              Ledger.record_verification(l, run, Map.put(verification, :artifact_refs, bad))
            end
          ],
          do: call

    task_calls =
      for bad <- [
            :not_list,
            [task | :tail],
            [task | "tail"],
            [task, task | %{tail: true}],
            List.duplicate(task, 33)
          ],
          do: fn -> Ledger.open(l, %{manifest() | tasks: bad}) end

    for call <- calls ++ task_calls do
      assert {:error, :invalid_record} = call.()
      assert Process.alive?(l)
      for _ <- 1..2, do: assert(Ledger.result(l, run) == {:ok, before})
      assert Ledger.status(l, run) == {:ok, status_before}
    end
  end

  test "invalid limits lists reject startup without affecting an existing ledger" do
    l = ledger()
    run = open(l)
    completed(l, run)
    assert {:ok, before} = Ledger.result(l, run)
    Process.flag(:trap_exit, true)

    for bad <- [
          [{:runs, 1} | :tail],
          [{:runs, 1} | "tail"],
          [{:runs, 1}, {:runs, 1} | %{}],
          List.duplicate({:runs, 1}, 33)
        ] do
      assert {:error, :invalid_limits} = Ledger.start_link(limits: bad)
      assert Process.alive?(l)
      assert Ledger.result(l, run) == {:ok, before}
    end
  end

  test "fail then re-pass restores eligibility but requires acceptance of new check IDs" do
    l = ledger()
    run = open(l)
    rev = revision(l, run, completed(l, run))
    review = approve(l, run, rev)
    assert {:ok, first_pass} = verify(l, run, rev)
    assert {:ok, first_acceptance} = accept(l, run, rev)
    assert {:ok, before} = Ledger.result(l, run)
    original = Enum.find(before.records, &(&1.id == first_acceptance))

    assert {:ok, %{tasks: %{"alpha" => %{eligible: true, accepted: true}}}} =
             Ledger.status(l, run)

    assert {:ok, _} = verify(l, run, rev, :failed, 1)

    assert {:ok, %{tasks: %{"alpha" => %{eligible: false, accepted: false}}}} =
             Ledger.status(l, run)

    assert {:ok, new_pass} = verify(l, run, rev)
    refute new_pass == first_pass

    for _ <- 1..2 do
      assert {:ok, %{tasks: %{"alpha" => %{eligible: true, accepted: false}}}} =
               Ledger.status(l, run)
    end

    assert {:ok, new_acceptance} = accept(l, run, rev)

    assert {:ok, %{tasks: %{"alpha" => %{eligible: true, accepted: true}}}} =
             Ledger.status(l, run)

    assert {:ok, snapshot} = Ledger.result(l, run)
    assert Enum.find(snapshot.records, &(&1.id == first_acceptance)) == original
    current = Enum.find(snapshot.records, &(&1.id == new_acceptance))
    assert current.review_ids == [review]
    assert current.verification_ids == [new_pass]
    # Even another pass with no intervening failure changes the evidence set.
    assert {:ok, _} = verify(l, run, rev)

    assert {:ok, %{tasks: %{"alpha" => %{eligible: true, accepted: false}}}} =
             Ledger.status(l, run)
  end

  test "new approving review requires acceptance of new review IDs" do
    l = ledger()
    run = open(l)
    rev = revision(l, run, completed(l, run))
    first_review = approve(l, run, rev)
    assert {:ok, pass} = verify(l, run, rev)
    assert {:ok, first_acceptance} = accept(l, run, rev)
    assert {:ok, before} = Ledger.result(l, run)
    original = Enum.find(before.records, &(&1.id == first_acceptance))
    attempt = completed(l, run, "alpha", %{kind: :review, subject_revision_id: rev})

    assert {:ok, _} =
             Ledger.record_review(l, run, %{
               revision_id: rev,
               review_attempt_id: attempt,
               verdict: :changes_requested,
               recorded_by: "caller"
             })

    assert {:ok, %{tasks: %{"alpha" => %{eligible: false, accepted: false}}}} =
             Ledger.status(l, run)

    new_review = approve(l, run, rev)
    refute new_review == first_review

    assert {:ok, %{tasks: %{"alpha" => %{eligible: true, accepted: false}}}} =
             Ledger.status(l, run)

    assert {:ok, new_acceptance} = accept(l, run, rev)

    assert {:ok, %{tasks: %{"alpha" => %{eligible: true, accepted: true}}}} =
             Ledger.status(l, run)

    assert {:ok, snapshot} = Ledger.result(l, run)
    assert Enum.find(snapshot.records, &(&1.id == first_acceptance)) == original
    current = Enum.find(snapshot.records, &(&1.id == new_acceptance))
    assert current.review_ids == [new_review]
    assert current.verification_ids == [pass]
    approve(l, run, rev)

    assert {:ok, %{tasks: %{"alpha" => %{eligible: true, accepted: false}}}} =
             Ledger.status(l, run)
  end

  test "abnormal linked starter death ends process-lifetime storage" do
    parent = self()

    {starter, starter_ref} =
      spawn_monitor(fn ->
        {:ok, l} = Ledger.start_link()
        run = open(l)
        send(parent, {:started, l, run})

        receive do
          :stop -> exit(:starter_failed)
        end
      end)

    assert_receive {:started, l, _run}
    ledger_ref = Process.monitor(l)
    send(starter, :stop)
    assert_receive {:DOWN, ^starter_ref, :process, ^starter, :starter_failed}
    assert_receive {:DOWN, ^ledger_ref, :process, ^l, :starter_failed}
  end
end

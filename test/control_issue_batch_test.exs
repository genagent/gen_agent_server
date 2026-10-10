Code.require_file("../examples/control_issue_batch.exs", __DIR__)

defmodule GenAgentServer.Examples.ControlIssueBatchTest do
  use ExUnit.Case, async: false
  alias GenAgentServer.Examples.ControlIssueBatch, as: Batch

  defp name, do: "issue-batch-#{System.unique_integer([:positive])}"

  defp config do
    %{
      "cwd" => File.cwd!(),
      "max_in_flight" => 2,
      "max_results" => 1,
      "routes" => [
        %{"name" => "worker", "provider" => "echo"},
        %{"name" => "reviewer", "provider" => "echo"}
      ]
    }
  end

  defp manifest do
    %{
      name: "synthetic caller batch",
      control_revision: "test-v1",
      tasks:
        Enum.map(
          ["alpha", "beta"],
          &%{
            name: &1,
            checkout: File.cwd!(),
            required_checks: ["smoke"]
          }
        )
    }
  end

  defp spec(task) do
    %{
      stage: "work",
      kind: :work,
      provider: "echo",
      requested_settings: %{},
      instruction_revision: "test-v1",
      checkout: File.cwd!(),
      prompt: "Implement #{task}"
    }
  end

  defp await(ctx, ids),
    do: Batch.await(ctx, ids, System.monotonic_time(:millisecond) + 5000)

  defp check(revision, executable, args \\ []) do
    %{
      revision_id: revision,
      check_name: "smoke",
      cwd: File.cwd!(),
      argv: [System.find_executable(executable) | args],
      recorded_by: "test manager"
    }
  end

  setup do
    {:ok, ctx} = Batch.start(name(), config(), manifest())
    on_exit(fn -> Batch.close(ctx) end)
    %{ctx: ctx}
  end

  test "two explicit tasks, review verdicts and a failed command denying acceptance", %{ctx: ctx} do
    work =
      for task <- ["alpha", "beta"] do
        assert {:ok, id} = Batch.submit(ctx, task, "worker", spec(task))
        assert {:ok, ^id} = Batch.submit(ctx, task, "worker", spec(task))
        {task, id}
      end

    assert {:ok, completed} = await(ctx, Enum.map(work, &elem(&1, 1)))
    assert {:ok, ^completed} = Batch.snapshot(ctx)
    assert {:ok, ^completed} = Batch.snapshot(ctx)

    subjects =
      for {task, work_id} <- work do
        assert completed.attempts[work_id].terminal.status == :completed
        assert String.contains?(completed.attempts[work_id].terminal.text, "compact output")
        # Manager-attested synthetic fingerprint, not a claim about real source changes.
        fingerprint = if task == "alpha", do: "a", else: "b"

        assert {:ok, revision} =
                 Batch.record_revision(ctx, %{
                   task: task,
                   produced_by_attempt_id: work_id,
                   content_sha256: String.duplicate(fingerprint, 64),
                   recorded_by: "test manager"
                 })

        review_spec =
          Map.merge(spec(task), %{
            stage: "review",
            kind: :review,
            subject_revision_id: revision,
            prompt: "APPROVE is only synthetic text for #{task}"
          })

        assert {:ok, review} = Batch.submit(ctx, task, "reviewer", review_spec)
        {task, revision, review}
      end

    assert {:ok, _} = await(ctx, Enum.map(subjects, &elem(&1, 2)))
    assert {:ok, before_verdicts} = Batch.evidence(ctx)
    refute Enum.any?(before_verdicts.records, &(&1.kind in [:review, :acceptance]))

    for {task, revision, review} <- subjects do
      assert {:ok, _} =
               Batch.record_review(ctx, %{
                 revision_id: revision,
                 review_attempt_id: review,
                 verdict: :approve,
                 recorded_by: "test manager"
               })

      executable = if task == "alpha", do: "true", else: "false"
      assert {:ok, command} = Batch.run_check(ctx, check(revision, executable))
      assert command.result.argv == check(revision, executable).argv
      assert command.result.cwd == File.cwd!()
      assert command.result.exit_status == if(task == "alpha", do: 0, else: 1)

      acceptance = %{revision_id: revision, decision: :accepted, recorded_by: "test manager"}

      if task == "alpha" do
        assert {:ok, _} = Batch.record_acceptance(ctx, acceptance)
      else
        assert {:error, :checks_not_passed} = Batch.record_acceptance(ctx, acceptance)
      end
    end

    assert {:ok, status} = Batch.status(ctx)
    assert status.tasks["alpha"].accepted
    refute status.tasks["beta"].eligible
    refute status.tasks["beta"].accepted
    assert {:ok, evidence} = Batch.evidence(ctx)
    assert {:ok, ^evidence} = Batch.evidence(ctx)
    assert evidence.reserved_bytes == 0

    {_, revision, _} = hd(subjects)
    assert {:ok, long} = Batch.run_check(ctx, check(revision, "printf", ["%05000d", "1"]))
    assert byte_size(long.result.output) == 4096
    assert String.ends_with?(long.result.output, "[output truncated]")
    # Multibyte output crosses the retained byte ceiling without corrupting UTF-8.
    unicode = String.duplicate("λ", 1500)

    assert {:ok, unicode_check} =
             Batch.run_check(ctx, check(revision, "printf", ["%s%s", unicode, unicode]))

    assert String.valid?(unicode_check.result.output)
    assert byte_size(unicode_check.result.output) <= 4096
    assert String.ends_with?(unicode_check.result.output, "[output truncated]")
    assert {:ok, invalid} = Batch.run_check(ctx, check(revision, "printf", ["\\377"]))
    assert invalid.result.exit_status == 0
    assert invalid.result.outcome == :failed
    assert String.valid?(invalid.result.output)
    assert invalid.result.output =~ "invalid UTF-8 output omitted; 1 bytes; sha256"

    assert {:error, :checks_not_passed} =
             Batch.record_acceptance(ctx, %{
               revision_id: revision,
               decision: :accepted,
               recorded_by: "test manager"
             })

    assert {:error, :invalid_check} = Batch.run_check(ctx, check(revision, "sh", ["-c", "true"]))

    assert {:error, :check_scope_mismatch} =
             Batch.run_check(
               ctx,
               Map.put(check(revision, "true"), :cwd, Path.dirname(File.cwd!()))
             )

    assert {:error, {:exception, _}} =
             Batch.run_check(
               ctx,
               Map.put(check(revision, "true"), :argv, ["/missing/issue-batch-command"])
             )
  end

  test "deadline expiry observes pending Echo without cancellation or replay", %{ctx: ctx} do
    [{owner, _}] = Registry.lookup(GenAgentServer.Registry, {:invocations, ctx.instance})
    :ok = :sys.suspend(owner)

    id =
      try do
        assert {:ok, id} = Batch.submit(ctx, "alpha", "worker", spec("alpha"))
        assert {:timeout, snapshot} = Batch.await(ctx, [id], System.monotonic_time(:millisecond))
        assert snapshot.attempts[id].terminal == nil
        assert snapshot.attempts[id].cancel == nil
        assert map_size(snapshot.attempts) == 1
        assert {:ok, ^id} = Batch.submit(ctx, "alpha", "worker", spec("alpha"))
        id
      after
        :ok = :sys.resume(owner)
      end

    assert {:ok, completed} = await(ctx, [id])
    assert completed.attempts[id].terminal.status == :completed
    assert completed.attempts[id].cancel == nil
    assert map_size(completed.attempts) == 1
    assert {:error, :unknown_attempt} = await(ctx, ["missing"])
  end

  test "explicit cleanup stops owned resources and is repeatable", %{ctx: ctx} do
    assert %{controller: :ok, run: :ok, instance: :ok, ledger: :ok} = Batch.close(ctx)
    refute Process.alive?(ctx.controller)
    refute Process.alive?(ctx.ledger)
    refute Process.alive?(ctx.instance_pid)
    assert Registry.lookup(GenAgentServer.Registry, {:instance, ctx.instance}) == []
    assert %{controller: :already_stopped, ledger: :already_stopped} = Batch.close(ctx)
  end

  test "partial startup cleans the instance and never takes ownership of an existing one", %{
    ctx: ctx
  } do
    instance = name()

    assert {:error, %{startup: {:error, :invalid_record}, cleanup: %{instance: :ok, ledger: :ok}}} =
             Batch.start(instance, config(), %{})

    assert Registry.lookup(GenAgentServer.Registry, {:instance, instance}) == []
    assert {:error, _} = Batch.start(ctx.instance, config(), manifest())
    assert Process.alive?(ctx.instance_pid)
    assert Process.alive?(ctx.controller)
  end
end

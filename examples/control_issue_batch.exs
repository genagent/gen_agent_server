defmodule GenAgentServer.Examples.ControlIssueBatch do
  @moduledoc """
  Optional caller harness; loading this file starts nothing.

  In IEx use `Code.require_file("examples/control_issue_batch.exs")`, or load it
  with `mix run -r examples/control_issue_batch.exs caller.exs`. The manager
  supplies an instance name, InstanceSpec config (routes, checkout, provider,
  model, effort and finite limits), and Ledger manifest (name, control_revision,
  tasks with name, checkout and required_checks). No classification or retries.

  `submit/4` takes the exact Controller/Ledger spec: stage, kind, provider,
  requested_settings, instruction_revision, checkout, inline prompt; a review
  also requires subject_revision_id. Requested settings attest the configured
  route, not overrides. Real review routes must explicitly configure read-only
  access. A compact-output request is appended to every prompt before submission.

  Record the manager's content_sha256 using `record_revision/2` with task,
  produced_by_attempt_id and recorded_by (optional base_commit/artifact_refs).
  `run_check/2` takes revision_id, check_name, argv, cwd and recorded_by.
  It runs direct argv only, in an existing absolute directory lexically within
  that revision's checkout. Common shell executable names are rejected; this is not a
  filesystem sandbox or symlink boundary. The manager must authorize each argv.
  Checks are synchronous; no command timeout or subprocess cleanup is promised.
  Output is retained up to 4096 bytes with a truncation marker. Invalid UTF-8
  output is omitted with a byte count/digest and records a failed check even if
  the command exited zero. Transient command
  output is not bounded. An execution error is returned without fabricated evidence.

  `record_review/2` takes revision_id, review_attempt_id, verdict, recorded_by
  (optional excerpt). `record_acceptance/2` takes revision_id, decision,
  recorded_by (optional reason). Only the manager decides these; Ledger enforces
  gates. Await completion is not acceptance. Timeouts return observations only.
  `close/1` explicitly stops the owned controller, instance PID and ledger;
  stopping these owners is not proof that provider subprocesses were cleaned up.
  These are process-lifetime resources; keep the returned context for cleanup.
  This harness establishes no real mixed-provider batch acceptance for #40.
  """
  alias GenAgentServer.Control.{Controller, Ledger}
  alias GenAgentServer.InstanceSpec

  @cap 4096
  @compact "\nReturn compact output, at most 4096 UTF-8 bytes."
  @shells ~w(sh bash dash zsh ksh csh tcsh fish powershell pwsh cmd cmd.exe)

  def start(instance, config, manifest) do
    with {:ok, spec} <- InstanceSpec.parse(instance, config),
         {:ok, pid} <-
           GenAgentServer.start_instance(
             instance,
             spec.agents,
             Keyword.put(spec.opts, :description, spec.description)
           ) do
      ctx = %{instance: instance, instance_pid: pid, ledger: nil, run: nil, controller: nil}

      case safely(fn -> Ledger.start_link() end) do
        {:ok, ledger} -> open_run(%{ctx | ledger: ledger}, manifest)
        error -> startup_error(ctx, error)
      end
    end
  end

  defp open_run(ctx, manifest) do
    case safely(fn -> Ledger.open(ctx.ledger, manifest) end) do
      {:ok, run} ->
        ctx = %{ctx | run: run}

        case safely(fn ->
               Controller.start_link(
                 instance: ctx.instance,
                 ledger: ctx.ledger,
                 run: run,
                 limits: [text_bytes: @cap]
               )
             end) do
          {:ok, controller} -> {:ok, %{ctx | controller: controller}}
          error -> startup_error(ctx, error)
        end

      error ->
        startup_error(ctx, error)
    end
  end

  defp startup_error(ctx, error), do: {:error, %{startup: error, cleanup: close(ctx)}}

  def submit(ctx, task, route, %{prompt: prompt} = spec) when is_binary(prompt) do
    spec = Map.put(spec, :prompt, prompt <> @compact)

    with :ok <- bounded_text(spec),
         :ok <- Ledger.validate_attempt_spec(spec) do
      Controller.submit(ctx.controller, task, route, spec)
    end
  end

  def submit(_, _, _, _), do: {:error, :inline_prompt_required}

  def snapshot(ctx), do: Controller.result(ctx.controller)
  def evidence(ctx), do: Ledger.result(ctx.ledger, ctx.run)
  def status(ctx), do: Ledger.status(ctx.ledger, ctx.run)

  @doc "Await IDs against an absolute System.monotonic_time(:millisecond) deadline."
  def await(ctx, ids, deadline) when is_list(ids) and is_integer(deadline) do
    with {:ok, snapshot} <- snapshot(ctx) do
      remaining = deadline - System.monotonic_time(:millisecond)

      cond do
        Enum.any?(ids, &(not Map.has_key?(snapshot.attempts, &1))) ->
          {:error, :unknown_attempt}

        Enum.all?(
          ids,
          &(snapshot.attempts[&1].execution in [
              :completed,
              :failed,
              :cancelled,
              :admission_failed
            ])
        ) ->
          {:ok, snapshot}

        remaining <= 0 ->
          {:timeout, snapshot}

        true ->
          Process.sleep(min(10, remaining))
          await(ctx, ids, deadline)
      end
    end
  end

  def record_revision(ctx, record), do: record(ctx, :record_revision, record)
  def record_review(ctx, record), do: record(ctx, :record_review, record)
  def record_acceptance(ctx, record), do: record(ctx, :record_acceptance, record)

  defp record(ctx, function, record) do
    with :ok <- bounded_text(record),
         do: apply(Ledger, function, [ctx.ledger, ctx.run, record])
  end

  def run_check(ctx, record) do
    with :ok <- check_input(record),
         {:ok, evidence} <- evidence(ctx),
         :ok <- check_scope(evidence, record),
         {:ok, {output, exit_status}} <- command(record) do
      valid_output = String.valid?(output)

      result =
        Map.merge(record, %{
          exit_status: exit_status,
          outcome: if(exit_status == 0 and valid_output, do: :passed, else: :failed),
          output: if(valid_output, do: capped_output(output), else: invalid_output(output))
        })

      case Ledger.record_verification(ctx.ledger, ctx.run, result) do
        {:ok, id} -> {:ok, %{record_id: id, result: result}}
        error -> {:error, %{recording: error, result: result}}
      end
    end
  end

  defp check_input(record) when is_map(record) do
    keys = [:revision_id, :check_name, :argv, :cwd, :recorded_by]
    argv = Map.get(record, :argv)

    if Enum.sort(Map.keys(record)) == Enum.sort(keys) and
         Enum.all?(
           keys -- [:argv],
           &(is_binary(record[&1]) and
               byte_size(record[&1]) in 1..@cap)
         ) and
         is_list(argv) and length(argv) in 1..32 and
         Enum.all?(
           argv,
           &(is_binary(&1) and byte_size(&1) <= @cap and
               not String.contains?(&1, <<0>>))
         ) and hd(argv) != "" and
         Path.basename(hd(argv)) not in @shells and
         Path.type(record.cwd) == :absolute and File.dir?(record.cwd),
       do: :ok,
       else: {:error, :invalid_check}
  end

  defp check_input(_), do: {:error, :invalid_check}

  defp check_scope(evidence, record) do
    revision =
      Enum.find(
        evidence.records,
        &(&1.kind == :revision and
            &1.id == record.revision_id)
      )

    task = revision && Enum.find(evidence.manifest.tasks, &(&1.name == revision.data.task))

    if task do
      checkout = task.checkout |> Path.expand() |> Path.split()
      cwd = record.cwd |> Path.expand() |> Path.split()

      if not evidence.closed and record.check_name in task.required_checks and
           Enum.take(cwd, length(checkout)) == checkout,
         do: :ok,
         else: {:error, :check_scope_mismatch}
    else
      {:error, :unknown_revision}
    end
  end

  defp command(%{argv: [executable | args], cwd: cwd}) do
    case safely(fn -> System.cmd(executable, args, cd: cwd, stderr_to_stdout: true) end) do
      {output, status} when is_binary(output) and is_integer(status) -> {:ok, {output, status}}
      error -> error
    end
  end

  defp invalid_output(output) do
    digest = :crypto.hash(:sha256, output) |> Base.encode16(case: :lower)
    "[invalid UTF-8 output omitted; #{byte_size(output)} bytes; sha256 #{digest}]"
  end

  defp capped_output(output) when byte_size(output) <= @cap, do: output

  defp capped_output(output) do
    marker = "\n[output truncated]"
    utf8_prefix(binary_part(output, 0, @cap - byte_size(marker))) <> marker
  end

  # Preserve a valid output prefix when the byte ceiling lands inside a codepoint.
  # Output validity is checked before capping; this repairs a boundary in
  # otherwise valid UTF-8.
  defp utf8_prefix(prefix) do
    case :unicode.characters_to_binary(prefix, :utf8, :utf8) do
      {:incomplete, valid, _tail} -> valid
      {:error, _valid, _tail} -> prefix
      valid -> valid
    end
  end

  defp bounded_text(record) when is_map(record) do
    if Enum.all?(record, fn {_key, value} ->
         not is_binary(value) or byte_size(value) <= @cap
       end), do: :ok, else: {:error, :text_limit}
  end

  defp bounded_text(_), do: {:error, :invalid_record}

  @doc "Return each cleanup result, attempting all owned resources even after an error."
  def close(ctx) do
    controller = stop(ctx.controller)
    run = if ctx.ledger && ctx.run, do: safely(fn -> Ledger.close(ctx.ledger, ctx.run) end)

    instance =
      safely(fn ->
        DynamicSupervisor.terminate_child(
          GenAgentServer.InstanceSupervisor,
          ctx.instance_pid
        )
      end)

    ledger = stop(ctx.ledger)
    %{controller: controller, run: run, instance: instance, ledger: ledger}
  end

  defp stop(nil), do: :not_started

  defp stop(pid),
    do:
      safely(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid), else: :already_stopped
      end)

  defp safely(fun) do
    fun.()
  rescue
    error -> {:error, {:exception, Exception.message(error)}}
  catch
    :exit, reason -> {:error, {:exit, reason}}
  end
end

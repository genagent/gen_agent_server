defmodule GenAgentServer.Control.Ledger do
  @moduledoc """
  Optional caller-started, process-lifetime evidence storage. This module performs
  no invocation, verification command, cancellation, publication or cleanup.
  All supplied evidence (including failures, timeouts and revision fingerprints)
  is a caller attestation, not a certification by the ledger.

  Start with `start_link(limits: keyword)`; optional `name` follows GenServer.
  Defaults are also hard ceilings; limits may only be lowered, never infinite:
  4 runs, 8 tasks/run, 64 attempts/run, 256 records/run, 65,536 encoded bytes/record
  and 4,194,304 encoded bytes overall. The manifest, each attempt specification,
  terminal and gate record each consume one record. Attempt admission reserves
  its terminal record slot. Bytes are the sum of Erlang
  external sizes of these immutable records, not a bound on VM memory/mailboxes.
  No individual record is evicted. `forget` frees an entire closed run with no
  unfinished attempts. `record_attempt/5` with `reserve_terminal: true` additionally
  reserves the configured record byte ceiling before caller invocation. All writes
  respect outstanding reservations across runs. A valid terminal within that ceiling
  consumes its own reservation; rejection preserves it. Ordinary attempts reserve
  no bytes and may fail to finish in a full store. `bytes` reports actual retained
  charges; run/status `reserved_bytes` reports outstanding capacity separately.
  Reserved attempts expose `reserved_bytes`, reset to zero on successful finish.

  Maps use atom keys and reject unknown keys, structs and arbitrary metadata.
  Strings are at most 4,096 bytes (prompt/text/output/excerpt up to the record byte limit).
  Lists have at most 32 elements. Paths are absolute caller attestations. Attempt
  checkouts must exactly match the declared task checkout. Verification cwd may
  equal or descend from that checkout after lexical normalization of both paths;
  supplied cwd is retained unchanged. No existence, realpath or symlink resolution
  is performed, and containment does not authorize filesystem access. Requested
  settings are a flat map of at most 16 scalar values. See README and the Echo
  example for input shapes. A missing terminal `text` becomes nil, whereas an
  explicitly empty text stays "". Unknown `actual_model` stays nil.

  Attempts and gate records are immutable; every call creates a new ID except
  exact duplicate terminal evidence, which is idempotent. Revision fingerprints
  are caller-supplied lowercase SHA-256 strings covering the intended content.
  Review attempts must name their subject revision. Acceptance uses the latest
  review and latest check per required name for the current revision; old passes
  cannot bypass later failures. Historical acceptances stay readable, but status
  recomputes eligibility after new evidence. Accepted status additionally requires
  the latest host acceptance to match the current review/check IDs exactly; new
  passing evidence requires a new acceptance. Acceptance never
  publishes or proves that the filesystem still matches the fingerprint.

  The ledger does not monitor callers. Death of an ordinary API caller leaves
  storage intact; death of the linked starter follows standard OTP link rules.
  Use caller-owned supervision if appropriate (child restart is `:temporary`).
  Ledger death loses all data; a new ledger has a new ID namespace, with no replay.
  Execution, permissions, admission/concurrency, deadlines and resource cleanup
  remain the raw API's and caller's responsibilities. Full server issue #40 stays
  open, including orchestration and two paid mixed-provider batches.
  """
  use GenServer, restart: :temporary

  @limits %{
    runs: 4,
    tasks_per_run: 8,
    attempts_per_run: 64,
    records_per_run: 256,
    record_bytes: 65_536,
    total_bytes: 4_194_304
  }

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, Keyword.get(opts, :limits, []), Keyword.take(opts, [:name]))
  end

  def open(server, manifest), do: GenServer.call(server, {:open, manifest})

  def record_attempt(server, run, task, spec, opts \\ []),
    do: GenServer.call(server, {:attempt, run, task, spec, opts})

  def finish_attempt(server, run, attempt, evidence),
    do: GenServer.call(server, {:finish, run, attempt, evidence})

  def record_revision(server, run, record),
    do: GenServer.call(server, {:record, run, :revision, record})

  def record_review(server, run, record),
    do: GenServer.call(server, {:record, run, :review, record})

  def record_verification(server, run, record),
    do: GenServer.call(server, {:record, run, :verification, record})

  def record_acceptance(server, run, record),
    do: GenServer.call(server, {:record, run, :acceptance, record})

  def close(server, run), do: GenServer.call(server, {:close, run})
  def forget(server, run), do: GenServer.call(server, {:forget, run})
  def result(server, run), do: GenServer.call(server, {:read, run, :result})
  def status(server, run), do: GenServer.call(server, {:read, run, :status})

  @impl true
  def init(overrides) do
    if bounded_list?(overrides, 32) and Keyword.keyword?(overrides) and
         Enum.all?(overrides, fn {k, v} ->
           is_integer(v) and v > 0 and v <= Map.get(@limits, k, 0)
         end) do
      {:ok,
       %{
         limits: Map.merge(@limits, Map.new(overrides)),
         runs: %{},
         bytes: 0,
         reserved_bytes: 0,
         serial: 0,
         namespace: Base.encode16(:crypto.strong_rand_bytes(12), case: :lower)
       }}
    else
      {:stop, :invalid_limits}
    end
  end

  @impl true
  def handle_call(request, _from, state) do
    case apply_request(request, state) do
      {:ok, reply, next} -> {:reply, reply, next}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  defp apply_request({:open, manifest}, state) do
    with :ok <- validate_manifest(manifest, state.limits),
         :ok <- require_true(map_size(state.runs) < state.limits.runs, :quota_exhausted) do
      {id, state} = next_id(state)
      entry = %{id: id, kind: :manifest, data: manifest}

      run = %{
        id: id,
        manifest: manifest,
        closed: false,
        attempts: %{},
        records: [],
        current_revisions: %{},
        record_count: 0,
        reserved_bytes: 0,
        bytes: 0
      }

      with {:ok, run, state} <- charge(run, state, entry) do
        {:ok, {:ok, id}, put_run(state, run)}
      end
    end
  end

  defp apply_request({:read, id, kind}, state) do
    with {:ok, run} <- fetch_run(state, id) do
      value = if kind == :result, do: run, else: summary(run)
      {:ok, {:ok, value}, state}
    end
  end

  defp apply_request({:close, id}, state) do
    with {:ok, run} <- fetch_run(state, id) do
      {:ok, :ok, put_run(state, %{run | closed: true})}
    end
  end

  defp apply_request({:forget, id}, state) do
    with {:ok, run} <- fetch_run(state, id),
         :ok <- require_true(run.closed, :not_closed),
         :ok <- require_true(not unfinished?(run), :unfinished_attempts) do
      {:ok, :ok, %{state | runs: Map.delete(state.runs, id), bytes: state.bytes - run.bytes}}
    end
  end

  defp apply_request({:attempt, run_id, task, spec, opts}, state) do
    with {:ok, reserve?} <- validate_attempt_opts(opts),
         {:ok, run} <- writable_run(state, run_id),
         {:ok, task_spec} <- fetch_task(run, task),
         :ok <- validate_spec(spec, state.limits),
         :ok <- require_true(spec.checkout == task_spec.checkout, :checkout_mismatch),
         :ok <- validate_subject(run, task, spec),
         :ok <-
           require_true(map_size(run.attempts) < state.limits.attempts_per_run, :quota_exhausted) do
      {id, state} = next_id(state)
      attempt = %{id: id, kind: :attempt, task: task, spec: spec, terminal: nil}

      reservation = if reserve?, do: state.limits.record_bytes, else: 0
      attempt = if reserve?, do: Map.put(attempt, :reserved_bytes, reservation), else: attempt

      with {:ok, run, state} <- charge(run, state, attempt, 2, reservation) do
        run = %{run | attempts: Map.put(run.attempts, id, copy(attempt))}
        {:ok, {:ok, id}, put_run(state, run)}
      end
    end
  end

  defp apply_request({:finish, run_id, id, evidence}, state) do
    # Closing stops new records/attempts, but permits finishing existing attempts.
    with {:ok, run} <- fetch_run(state, run_id),
         {:ok, attempt} <- fetch_attempt(run, id),
         :ok <- validate_evidence(evidence, state.limits) do
      evidence = Map.merge(%{text: nil, actual_model: nil}, evidence)

      cond do
        attempt.terminal == evidence ->
          {:ok, :ok, state}

        attempt.terminal != nil ->
          {:error, :conflict}

        true ->
          entry = %{kind: :terminal, attempt_id: id, data: evidence}

          reservation = Map.get(attempt, :reserved_bytes, 0)

          with {:ok, run, state} <- charge(run, state, entry, 0, -reservation) do
            attempt =
              if Map.has_key?(attempt, :reserved_bytes),
                do: %{attempt | reserved_bytes: 0},
                else: attempt

            run = %{
              run
              | attempts: Map.put(run.attempts, id, %{attempt | terminal: copy(evidence)})
            }

            {:ok, :ok, put_run(state, run)}
          end
      end
    end
  end

  defp apply_request({:record, run_id, kind, data}, state) do
    with {:ok, run} <- writable_run(state, run_id),
         :ok <- validate_record(kind, data, state.limits),
         {:ok, extra} <- record_refs(kind, data, run) do
      {id, state} = next_id(state)
      entry = Map.merge(%{id: id, kind: kind, data: data}, extra)

      with {:ok, run, state} <- charge(run, state, entry) do
        run = %{run | records: run.records ++ [copy(entry)]}

        run =
          if kind == :revision,
            do: %{run | current_revisions: Map.put(run.current_revisions, data.task, id)},
            else: run

        {:ok, {:ok, id}, put_run(state, run)}
      end
    end
  end

  defp record_refs(:revision, data, run) do
    with {:ok, _} <- fetch_task(run, data.task),
         {:ok, attempt} <- fetch_attempt(run, data.produced_by_attempt_id),
         :ok <-
           require_true(
             attempt.task == data.task and attempt.spec.kind == :work and
               match?(%{status: :completed}, attempt.terminal),
             :invalid_producer
           ) do
      {:ok, %{}}
    end
  end

  defp record_refs(:review, data, run) do
    with {:ok, revision} <- fetch_revision(run, data.revision_id),
         {:ok, attempt} <- fetch_attempt(run, data.review_attempt_id),
         :ok <-
           require_true(
             attempt.task == revision.data.task and attempt.spec.kind == :review and
               attempt.spec.subject_revision_id == data.revision_id and
               match?(%{status: :completed}, attempt.terminal),
             :invalid_review
           ) do
      {:ok, %{}}
    end
  end

  defp record_refs(:verification, data, run) do
    with {:ok, revision} <- fetch_revision(run, data.revision_id),
         {:ok, task} <- fetch_task(run, revision.data.task),
         :ok <- require_true(within_checkout?(data.cwd, task.checkout), :checkout_mismatch),
         :ok <- require_true(data.outcome != :passed or data.exit_status == 0, :invalid_pass) do
      {:ok, %{}}
    end
  end

  defp record_refs(:acceptance, data, run) do
    with {:ok, revision} <- fetch_revision(run, data.revision_id) do
      if data.decision == :rejected do
        {:ok, %{review_ids: [], verification_ids: []}}
      else
        with {:ok, review, checks} <- gates(run, revision) do
          {:ok, %{review_ids: [review.id], verification_ids: Enum.map(checks, & &1.id)}}
        end
      end
    end
  end

  defp gates(run, revision) do
    task = revision.data.task
    {:ok, task_spec} = fetch_task(run, task)
    review = latest(run, :review, revision.id)
    checks = Enum.map(task_spec.required_checks, &latest(run, :verification, revision.id, &1))

    with :ok <- require_true(run.current_revisions[task] == revision.id, :stale_revision),
         :ok <- require_true(not unfinished?(run, task), :unfinished_attempts),
         :ok <- require_true(review != nil and review.data.verdict == :approve, :missing_approval),
         :ok <-
           require_true(
             Enum.all?(checks, fn c ->
               c != nil and c.data.outcome == :passed and c.data.exit_status == 0
             end),
             :checks_not_passed
           ) do
      {:ok, review, checks}
    end
  end

  defp latest(run, kind, revision, check \\ nil) do
    run.records
    |> Enum.reverse()
    |> Enum.find(fn r ->
      r.kind == kind and r.data.revision_id == revision and
        (check == nil or r.data.check_name == check)
    end)
  end

  defp summary(run) do
    tasks =
      Map.new(run.manifest.tasks, fn task ->
        revision = run.current_revisions[task.name]
        gate = with {:ok, r} <- fetch_revision(run, revision), do: gates(run, r)
        acceptance = latest(run, :acceptance, revision)
        eligible = match?({:ok, _, _}, gate)

        accepted =
          case gate do
            {:ok, review, checks} ->
              acceptance != nil and acceptance.data.decision == :accepted and
                acceptance.review_ids == [review.id] and
                acceptance.verification_ids == Enum.map(checks, & &1.id)

            _ ->
              false
          end

        {task.name,
         %{
           current_revision_id: revision,
           eligible: eligible,
           accepted: accepted
         }}
      end)

    %{
      id: run.id,
      closed: run.closed,
      tasks: tasks,
      attempts: map_size(run.attempts),
      records: run.record_count,
      bytes: run.bytes,
      reserved_bytes: run.reserved_bytes
    }
  end

  # Match only the two supported bounded shapes; never traverse caller option lists.
  defp validate_attempt_opts([]), do: {:ok, false}

  defp validate_attempt_opts([{:reserve_terminal, value}]) when is_boolean(value),
    do: {:ok, value}

  defp validate_attempt_opts(_), do: {:error, :invalid_options}

  defp validate_manifest(m, limits) do
    with :ok <- fields(m, [name: :string, control_revision: :string, tasks: :tasks], [], limits),
         :ok <-
           require_true(
             length(m.tasks) > 0 and length(m.tasks) <= limits.tasks_per_run,
             :quota_exhausted
           ),
         :ok <-
           require_true(
             length(Enum.uniq_by(m.tasks, & &1.name)) == length(m.tasks),
             :duplicate_task
           ) do
      :ok
    end
  end

  defp validate_spec(s, limits) do
    with :ok <-
           fields(
             s,
             [
               stage: :string,
               kind: {:enum, [:work, :review]},
               provider: :string,
               requested_settings: :settings,
               instruction_revision: :string,
               checkout: :path
             ],
             [prompt: :text, prompt_ref: :string, subject_revision_id: :string],
             limits
           ),
         :ok <-
           require_true(Map.has_key?(s, :prompt) != Map.has_key?(s, :prompt_ref), :invalid_prompt),
         :ok <-
           require_true(
             s.kind == :review == Map.has_key?(s, :subject_revision_id),
             :invalid_subject
           ) do
      :ok
    end
  end

  defp validate_subject(run, task, %{kind: :review, subject_revision_id: id}) do
    with {:ok, revision} <- fetch_revision(run, id),
         :ok <- require_true(revision.data.task == task, :invalid_subject),
         do: :ok
  end

  defp validate_subject(_, _, _), do: :ok

  defp validate_evidence(e, limits) do
    fields(
      e,
      [status: {:enum, [:completed, :failed, :timed_out, :cancelled, :admission_failed]}],
      [
        text: :nullable_text,
        actual_model: :nullable_string,
        invocation_id: :string,
        session_id: :string,
        failure: :string,
        artifact_refs: :strings
      ],
      limits
    )
  end

  defp validate_record(:revision, d, l),
    do:
      fields(
        d,
        [
          task: :string,
          produced_by_attempt_id: :string,
          content_sha256: :sha256,
          recorded_by: :string
        ],
        [base_commit: :string, artifact_refs: :strings],
        l
      )

  defp validate_record(:review, d, l),
    do:
      fields(
        d,
        [
          revision_id: :string,
          review_attempt_id: :string,
          verdict: {:enum, [:approve, :changes_requested, :unknown]},
          recorded_by: :string
        ],
        [excerpt: :text],
        l
      )

  defp validate_record(:verification, d, l),
    do:
      fields(
        d,
        [
          revision_id: :string,
          check_name: :string,
          cwd: :path,
          argv: :argv,
          exit_status: :exit_status,
          outcome: {:enum, [:passed, :failed, :timed_out, :not_run]},
          recorded_by: :string
        ],
        [output: :text, artifact_refs: :strings],
        l
      )

  defp validate_record(:acceptance, d, l),
    do:
      fields(
        d,
        [revision_id: :string, decision: {:enum, [:accepted, :rejected]}, recorded_by: :string],
        [reason: :string],
        l
      )

  # Small shared validation for closed maps; no opaque recursively nested payloads.
  defp fields(map, required, optional, limits) when is_map(map) and not is_struct(map) do
    allowed = required ++ optional

    if map_size(map) <= length(allowed) and
         Enum.all?(required, fn {key, _} -> Map.has_key?(map, key) end) and
         Enum.all?(map, fn {key, value} ->
           case List.keyfind(allowed, key, 0) do
             {^key, type} -> valid?(value, type, limits)
             nil -> false
           end
         end), do: :ok, else: {:error, :invalid_record}
  end

  defp fields(_, _, _, _), do: {:error, :invalid_record}

  defp valid?(v, :string, _), do: is_binary(v) and byte_size(v) in 1..4096
  defp valid?(v, :text, l), do: is_binary(v) and byte_size(v) <= l.record_bytes
  defp valid?(v, :nullable_text, l), do: v == nil or valid?(v, :text, l)
  defp valid?(v, :nullable_string, l), do: v == nil or valid?(v, :string, l)
  defp valid?(v, :path, l), do: valid?(v, :string, l) and Path.type(v) == :absolute

  defp valid?(v, :sha256, _),
    do: is_binary(v) and byte_size(v) == 64 and String.match?(v, ~r/\A[0-9a-f]{64}\z/)

  defp valid?(v, :exit_status, _), do: v == nil or (is_integer(v) and v >= 0 and v <= 255)
  defp valid?(v, {:enum, values}, _), do: v in values

  defp valid?(v, :strings, l),
    do: bounded_list?(v, 32) and Enum.all?(v, &valid?(&1, :string, l))

  defp valid?(v, :argv, _limits),
    do:
      bounded_list?(v, 32) and v != [] and
        Enum.all?(v, fn arg -> is_binary(arg) and byte_size(arg) <= 4096 end) and hd(v) != ""

  defp valid?(v, :tasks, l),
    do:
      bounded_list?(v, 32) and
        Enum.all?(
          v,
          &(fields(&1, [name: :string, checkout: :path, required_checks: :strings], [], l) == :ok and
              length(&1.required_checks) == length(Enum.uniq(&1.required_checks)))
        )

  defp valid?(v, :settings, l),
    do:
      is_map(v) and not is_struct(v) and map_size(v) <= 16 and
        Enum.all?(v, fn {k, value} ->
          valid?(k, :string, l) and
            (value == nil or is_boolean(value) or
               (is_integer(value) and abs(value) <= 1_000_000_000) or valid?(value, :string, l))
        end)

  # Both paths have already been validated as absolute caller attestations.
  defp within_checkout?(cwd, checkout) do
    cwd_parts = cwd |> Path.expand() |> Path.split()
    checkout_parts = checkout |> Path.expand() |> Path.split()
    Enum.take(cwd_parts, length(checkout_parts)) == checkout_parts
  end

  # Reject improper tails and stop at the bound before length/Enum traversal.
  defp bounded_list?([], _remaining), do: true

  defp bounded_list?([_ | tail], remaining) when remaining > 0,
    do: bounded_list?(tail, remaining - 1)

  defp bounded_list?(_, _remaining), do: false

  defp charge(run, state, entry, slots \\ 1, reservation_delta \\ 0) do
    bytes = :erlang.external_size(entry)

    reserved_bytes = state.reserved_bytes + reservation_delta

    if bytes <= state.limits.record_bytes and
         state.bytes + bytes + reserved_bytes <= state.limits.total_bytes and
         run.record_count + slots <= state.limits.records_per_run do
      {:ok,
       %{
         run
         | bytes: run.bytes + bytes,
           record_count: run.record_count + slots,
           reserved_bytes: run.reserved_bytes + reservation_delta
       }, %{state | bytes: state.bytes + bytes, reserved_bytes: reserved_bytes}}
    else
      {:error, :quota_exhausted}
    end
  end

  defp next_id(state) do
    serial = state.serial + 1
    {state.namespace <> "/" <> Integer.to_string(serial), %{state | serial: serial}}
  end

  defp put_run(state, run), do: %{state | runs: Map.put(state.runs, run.id, copy(run))}
  defp copy(v) when is_binary(v), do: :binary.copy(v)
  defp copy(v) when is_list(v), do: Enum.map(v, &copy/1)
  defp copy(v) when is_map(v), do: Map.new(v, fn {k, value} -> {copy(k), copy(value)} end)
  defp copy(v), do: v
  defp require_true(true, _), do: :ok
  defp require_true(false, reason), do: {:error, reason}
  defp fetch_run(state, id), do: fetch(state.runs, id)
  defp fetch_attempt(run, id), do: fetch(run.attempts, id)

  defp fetch(map, id) do
    case Map.fetch(map, id) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, :not_found}
    end
  end

  defp fetch_task(run, name) do
    case Enum.find(run.manifest.tasks, &(&1.name == name)) do
      nil -> {:error, :not_found}
      task -> {:ok, task}
    end
  end

  defp fetch_revision(run, id) do
    case Enum.find(run.records, &(&1.kind == :revision and &1.id == id)) do
      nil -> {:error, :not_found}
      revision -> {:ok, revision}
    end
  end

  defp writable_run(state, id) do
    with {:ok, run} <- fetch_run(state, id),
         :ok <- require_true(not run.closed, :closed),
         do: {:ok, run}
  end

  defp unfinished?(run, task \\ nil),
    do:
      Enum.any?(run.attempts, fn {_, a} ->
        a.terminal == nil and (task == nil or a.task == task)
      end)
end

defmodule GenAgentServer.Control.Controller do
  @moduledoc """
  Optional caller-started first #40 increment for independent work stages.

  Start with `instance: name, ledger: pid, run: run_id`. The caller owns one
  controller per fresh run, the configured instance and the ledger. Each
  task/stage is submitted once; identical submissions return the same ledger
  attempt ID. No queue, retries, restart recovery, reviews or gate automation.
  `status/1` and `result/1` return the same repeatable bounded snapshot.

  Limits may only be lowered: unfinished: 8, retained: 64, helpers: 8,
  helper_timeout_ms: 5_000, text_bytes: 4_096. Uncertainty and evidence failures
  continue to consume unfinished capacity. Helpers bound controller waiting,
  not provider execution. Cancel returns a request observation immediately;
  its later acknowledgement is separate from authoritative completion.
  Timeout never cancels work. Invocations PID loss fences completion permanently.
  Ledger unavailability stops new work but permits bounded observations from the
  original invocation lifetime. It also refuses new controller cancel requests;
  callers with a known ID may explicitly cancel through raw Invocations. Call timeout is availability uncertainty, not
  proof of ledger death; only the monitor establishes that death. Observed
  terminal execution survives evidence loss even when no ledger terminal fits.
  An uncertain admission may leave invocation_id unknown; cancel cannot target
  it before a completion notification supplies that ID. The caller may inspect
  raw Invocations separately; missing ID does not prove unsupported cancellation.

  Results retain text only within text_bytes and the ledger reservation,
  never events or arbitrary metadata. Oversized/invalid evidence leaves the
  ledger attempt unfinished with an explicit evidence_error, byte count and
  digest where available. No excerpt is presented as complete output. Actual
  model remains nil: the Response contract supplies no canonical model field.
  Retention bounds do not bound transient completion messages or VM memory.
  Stopping the controller kills its helpers, never shared owners or providers.
  """
  use GenServer, restart: :temporary
  alias GenAgentServer.Control.Ledger

  @limits %{unfinished: 8, retained: 64, helpers: 8, helper_timeout_ms: 5_000, text_bytes: 4_096}

  def start_link(opts) do
    if bounded_list?(opts, 5) and Keyword.keyword?(opts) and
         length(Enum.uniq_by(opts, &elem(&1, 0))) == length(opts) and
         Enum.all?(opts, fn {k, _} -> k in [:instance, :ledger, :run, :limits, :name] end) and
         is_binary(opts[:instance]) and byte_size(opts[:instance]) in 1..64 and
         is_pid(opts[:ledger]) and is_binary(opts[:run]) and byte_size(opts[:run]) in 1..4096 do
      GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
    else
      {:error, :invalid_options}
    end
  end

  def submit(server, task, route, spec), do: GenServer.call(server, {:submit, task, route, spec})
  def status(server), do: GenServer.call(server, :snapshot)
  def result(server), do: status(server)
  def cancel(server, attempt), do: GenServer.call(server, {:cancel, attempt})

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    with {:ok, limits} <- limits(Keyword.get(opts, :limits, [])),
         ledger when is_pid(ledger) <- Keyword.get(opts, :ledger),
         [{owner, _}] <- Registry.lookup(GenAgentServer.Registry, {:invocations, opts[:instance]}),
         owner_ref = Process.monitor(owner),
         ledger_ref = Process.monitor(ledger),
         {:ok, %{configured: true, routes: routes}} <- GenServer.call(owner, :describe),
         {:ok, run} <- Ledger.result(ledger, opts[:run]),
         true <- map_size(run.attempts) == 0 and not run.closed do
      {:ok,
       %{
         owner: owner,
         ledger: ledger,
         owner_ref: owner_ref,
         ledger_ref: ledger_ref,
         run: run.id,
         instance: opts[:instance],
         routes: Map.new(routes, &{&1.name, &1}),
         tasks: Map.new(run.manifest.tasks, &{&1.name, &1}),
         limits: limits,
         attempts: %{},
         keys: %{},
         refs: %{},
         helpers: %{},
         owner_lost: false,
         ledger_unavailable: nil,
         unavailable: nil
       }}
    else
      {:error, reason} -> {:stop, reason}
      _ -> {:stop, :invalid_controller_owners_or_run}
    end
  catch
    :exit, _ -> {:stop, :owner_unavailable}
  end

  @impl true
  def handle_call(:snapshot, _, s) do
    attempts =
      Map.new(s.attempts, fn {id, a} -> {id, Map.drop(a, [:spec, :ref, :completion_seen])} end)

    {:reply,
     {:ok,
      %{
        run: s.run,
        unavailable: s.unavailable,
        owner_lost: s.owner_lost,
        ledger_unavailable: s.ledger_unavailable,
        attempts: attempts,
        unfinished: unfinished(s)
      }}, s}
  end

  def handle_call({:submit, task, route, spec}, _, s) do
    with :ok <- Ledger.validate_attempt_spec(spec),
         :ok <- validate_route(s, task, route, spec) do
      key = {task, spec.stage}

      case s.keys[key] do
        nil ->
          admit(s, task, route, spec)

        id ->
          a = s.attempts[id]
          reply = if a.spec == spec and a.route == route, do: {:ok, id}, else: {:error, :conflict}
          {:reply, reply, s}
      end
    else
      {:error, reason} -> {:reply, {:error, reason}, s}
    end
  end

  def handle_call({:cancel, id}, _, s) do
    a = s.attempts[id]

    cond do
      a == nil ->
        {:reply, {:error, :not_found}, s}

      a.cancel != nil ->
        {:reply, {:ok, a.cancel}, s}

      a.terminal != nil ->
        {:reply, {:error, :already_finished}, s}

      s.owner_lost ->
        {:reply, {:error, :owner_unavailable}, s}

      s.ledger_unavailable != nil ->
        {:reply, {:error, :ledger_unavailable}, s}

      a.invocation_id == nil ->
        {:reply, {:error, :not_admitted}, s}

      map_size(s.helpers) >= s.limits.helpers ->
        {:reply, {:error, :busy}, s}

      true ->
        s = put_attempt(s, id, %{a | cancel: :requested})
        owner = s.owner

        s =
          helper(s, id, :cancel, fn ->
            GenServer.call(owner, {:cancel, a.invocation_id}, :infinity)
          end)

        {:reply, {:ok, :requested}, s}
    end
  end

  defp admit(s, task, route, spec) do
    cond do
      s.owner_lost ->
        {:reply, {:error, :owner_unavailable}, s}

      s.ledger_unavailable != nil ->
        {:reply, {:error, :ledger_unavailable}, s}

      unfinished(s) >= s.limits.unfinished or map_size(s.attempts) >= s.limits.retained or
          map_size(s.helpers) >= s.limits.helpers ->
        {:reply, {:error, :busy}, s}

      true ->
        case Ledger.record_attempt(s.ledger, s.run, task, spec, reserve_terminal: true) do
          {:ok, id} ->
            task = :binary.copy(task)
            route = :binary.copy(route)
            spec = copy(spec)
            key = {task, spec.stage}
            ref = make_ref()

            a = %{
              task: task,
              stage: spec.stage,
              provider: spec.provider,
              requested_settings: spec.requested_settings,
              route: route,
              spec: spec,
              ref: ref,
              execution: :admitting,
              invocation_id: nil,
              terminal: nil,
              evidence_error: nil,
              completion_seen: false,
              cancel: nil,
              text_bytes: nil,
              text_sha256: nil
            }

            s = %{s | keys: Map.put(s.keys, key, id), refs: Map.put(s.refs, ref, id)}
            s = put_attempt(s, id, a)
            recipient = self()
            owner = s.owner

            s =
              helper(s, id, :admit, fn ->
                GenServer.call(
                  owner,
                  {:invoke, route, spec.prompt, [recipient: recipient, recipient_ref: ref]},
                  :infinity
                )
              end)

            {:reply, {:ok, id}, s}

          error ->
            {:reply, error, s}
        end
    end
  catch
    :exit, reason -> {:reply, {:error, :ledger_unavailable}, fence(s, ledger_call_reason(reason))}
  end

  defp validate_route(s, task, route, spec) do
    t = s.tasks[task]
    r = s.routes[route]

    cond do
      spec.kind != :work or not Map.has_key?(spec, :prompt) ->
        {:error, :unsupported_attempt}

      t == nil ->
        {:error, :unknown_task}

      r == nil ->
        {:error, :unknown_route}

      spec.checkout != t.checkout or
          (spec.checkout != r.cwd and not (r.provider == "echo" and r.cwd == nil)) ->
        {:error, :checkout_mismatch}

      spec.provider != r.provider ->
        {:error, :provider_mismatch}

      not Enum.all?(spec.requested_settings, fn {k, v} ->
        Enum.any?(Map.drop(r, [:name, :provider, :cwd]), fn {rk, rv} ->
          Atom.to_string(rk) == k and setting(rv) == v
        end)
      end) ->
        {:error, :settings_mismatch}

      true ->
        :ok
    end
  end

  defp setting(v) when is_atom(v) and not is_nil(v) and not is_boolean(v), do: Atom.to_string(v)
  defp setting(v), do: v

  defp helper(s, id, kind, fun) do
    parent = self()
    tag = make_ref()

    {pid, monitor} =
      :erlang.spawn_opt(fn -> send(parent, {:helper, tag, fun.()}) end, [:link, :monitor])

    timer = Process.send_after(self(), {:helper_timeout, tag}, s.limits.helper_timeout_ms)

    %{
      s
      | helpers:
          Map.put(s.helpers, tag, %{id: id, kind: kind, pid: pid, monitor: monitor, timer: timer})
    }
  end

  @impl true
  def handle_info({:helper, tag, reply}, s) do
    case pop_helper(s, tag) do
      {nil, s} -> {:noreply, s}
      {h, s} -> {:noreply, helper_reply(s, h, reply)}
    end
  end

  def handle_info({:helper_timeout, tag}, s) do
    case pop_helper(s, tag) do
      {nil, s} ->
        {:noreply, s}

      {h, s} ->
        Process.exit(h.pid, :kill)
        {:noreply, uncertain(s, h)}
    end
  end

  def handle_info({:DOWN, ref, :process, _, _}, s) when ref == s.owner_ref or ref == s.ledger_ref,
    do: {:noreply, fence(s, if(ref == s.owner_ref, do: :invocations_lost, else: :ledger_lost))}

  def handle_info({:DOWN, ref, :process, _, _}, s) do
    case Enum.find(s.helpers, fn {_, h} -> h.monitor == ref end) do
      nil ->
        {:noreply, s}

      {tag, _} ->
        {h, s} = pop_helper(s, tag)
        {:noreply, uncertain(s, h)}
    end
  end

  def handle_info(
        {:gen_agent_server, :completion,
         %{recipient_ref: ref, invocation_id: inv, instance: instance}, result},
        s
      ) do
    id = s.refs[ref]

    if id != nil and instance == s.instance and not s.owner_lost do
      a = s.attempts[id]

      if not a.completion_seen and
           a.execution not in [:completed, :failed, :cancelled, :admission_failed] do
        a = %{a | completion_seen: true}

        if is_binary(inv) and byte_size(inv) in 1..4096 do
          s = put_attempt(s, id, %{a | invocation_id: :binary.copy(inv)})
          {:noreply, complete(s, id, result)}
        else
          {:noreply, evidence_error(put_attempt(s, id, a), id, :invalid_completion)}
        end
      else
        {:noreply, s}
      end
    else
      {:noreply, s}
    end
  end

  def handle_info({:EXIT, _, _}, s), do: {:noreply, s}
  def handle_info(_, s), do: {:noreply, s}

  defp helper_reply(s, %{kind: :cancel, id: id}, reply),
    do: put_attempt(s, id, %{s.attempts[id] | cancel: bounded_reply(reply)})

  defp helper_reply(s, %{kind: :admit, id: id} = h, reply) do
    a = s.attempts[id]

    cond do
      s.unavailable != nil or a.execution != :admitting ->
        s

      match?({:ok, inv} when is_binary(inv), reply) ->
        {:ok, inv} = reply
        put_attempt(s, id, %{a | invocation_id: inv, execution: :pending})

      match?({:error, _}, reply) ->
        {:error, reason} = reply

        finish(s, id, %{
          status: :admission_failed,
          text: nil,
          actual_model: nil,
          failure: reason_text(reason)
        })

      true ->
        uncertain(s, h)
    end
  end

  defp uncertain(s, %{id: id, kind: :cancel}),
    do: put_attempt(s, id, %{s.attempts[id] | cancel: :uncertain})

  defp uncertain(s, %{id: id}) do
    a = s.attempts[id]
    if a.execution == :admitting, do: put_attempt(s, id, %{a | execution: :unobserved}), else: s
  end

  defp complete(s, id, {:ok, :completed, response}) when is_map(response) do
    text = Map.get(response, :text)
    a = s.attempts[id]
    bytes = if is_binary(text), do: byte_size(text), else: nil

    digest =
      if is_binary(text), do: Base.encode16(:crypto.hash(:sha256, text), case: :lower), else: nil

    s = put_attempt(s, id, %{a | text_bytes: bytes, text_sha256: digest, execution: :completed})

    cond do
      text != nil and not is_binary(text) ->
        evidence_error(s, id, :invalid_text)

      is_binary(text) and (bytes > s.limits.text_bytes or not String.valid?(text)) ->
        evidence_error(s, id, :output_not_retainable)

      true ->
        # No canonical actual-model field in GenAgent.Response; do not infer it.
        evidence = %{
          status: :completed,
          text: if(is_binary(text), do: :binary.copy(text), else: nil),
          actual_model: nil,
          invocation_id: a.invocation_id
        }

        session = Map.get(response, :session_id)

        if session == nil or (is_binary(session) and byte_size(session) in 1..4096) do
          evidence =
            if session == nil,
              do: evidence,
              else: Map.put(evidence, :session_id, :binary.copy(session))

          finish(s, id, evidence)
        else
          evidence_error(s, id, :invalid_session_id)
        end
    end
  end

  defp complete(s, id, {:ok, :failed, reason}) do
    status = if reason == :cancelled, do: :cancelled, else: :failed

    finish(s, id, %{
      status: status,
      text: nil,
      actual_model: nil,
      invocation_id: s.attempts[id].invocation_id,
      failure: reason_text(reason)
    })
  end

  defp complete(s, id, _), do: evidence_error(s, id, :invalid_completion)

  defp finish(s, id, evidence) do
    s = put_attempt(s, id, %{s.attempts[id] | execution: evidence.status})

    if s.ledger_unavailable != nil do
      evidence_error(s, id, :ledger_unavailable)
    else
      case finish_evidence(s, id, evidence) do
        :ok ->
          put_attempt(s, id, %{s.attempts[id] | terminal: evidence})

        {:error, reason} ->
          evidence_error(s, id, reason)

        {:exit, reason} ->
          fence(evidence_error(s, id, :ledger_unavailable), ledger_call_reason(reason))
      end
    end
  end

  defp finish_evidence(s, id, evidence) do
    Ledger.finish_attempt(s.ledger, s.run, id, evidence)
  catch
    :exit, reason -> {:exit, reason}
  end

  # A failed call establishes availability uncertainty, not a monitored death.
  defp ledger_call_reason({:timeout, _}), do: :ledger_call_uncertain
  defp ledger_call_reason(_), do: :ledger_unavailable

  defp evidence_error(s, id, reason),
    do: put_attempt(s, id, %{s.attempts[id] | evidence_error: reason})

  defp reason_text(reason),
    do: inspect(reason, limit: 8, printable_limit: 256, width: 256) |> String.slice(0, 512)

  defp bounded_reply({:ok, ack}) when ack in [:cancelled, :cancelled_unconfirmed], do: {:ok, ack}
  defp bounded_reply({:error, reason}), do: {:error, reason_text(reason)}
  defp bounded_reply(_), do: :uncertain
  defp unfinished(s), do: Enum.count(s.attempts, fn {_, a} -> a.terminal == nil end)
  defp put_attempt(s, id, a), do: %{s | attempts: Map.put(s.attempts, id, a)}

  defp pop_helper(s, tag) do
    case Map.pop(s.helpers, tag) do
      {nil, _} ->
        {nil, s}

      {h, helpers} ->
        Process.cancel_timer(h.timer)
        Process.unlink(h.pid)
        Process.demonitor(h.monitor, [:flush])
        {h, %{s | helpers: helpers}}
    end
  end

  defp fence(s, reason) do
    Enum.each(s.helpers, fn {_, h} -> Process.exit(h.pid, :kill) end)

    owner_lost = s.owner_lost or reason == :invocations_lost

    ledger_unavailable =
      if reason == :invocations_lost, do: s.ledger_unavailable, else: reason

    attempts =
      Map.new(s.attempts, fn {id, a} ->
        a = if a.execution in [:admitting, :pending], do: %{a | execution: :unobserved}, else: a

        a =
          if ledger_unavailable != nil and a.terminal == nil,
            do: %{a | evidence_error: a.evidence_error || :ledger_unavailable},
            else: a

        {id, a}
      end)

    %{
      s
      | unavailable: s.unavailable || reason,
        owner_lost: owner_lost,
        ledger_unavailable: ledger_unavailable,
        attempts: attempts
    }
  end

  @impl true
  def terminate(_, s), do: Enum.each(s.helpers, fn {_, h} -> Process.exit(h.pid, :kill) end)

  defp limits(overrides) do
    if not bounded_list?(overrides, 5),
      do: {:error, :invalid_limits},
      else: checked_limits(overrides)
  end

  defp checked_limits(overrides) do
    if Keyword.keyword?(overrides) and
         length(Enum.uniq_by(overrides, &elem(&1, 0))) == length(overrides) and
         Enum.all?(overrides, fn {k, v} ->
           is_integer(v) and v > 0 and v <= Map.get(@limits, k, 0)
         end), do: {:ok, Map.merge(@limits, Map.new(overrides))}, else: {:error, :invalid_limits}
  end

  defp copy(v) when is_binary(v), do: :binary.copy(v)
  defp copy(v) when is_map(v), do: Map.new(v, fn {k, value} -> {copy(k), copy(value)} end)
  defp copy(v), do: v

  defp bounded_list?([], _), do: true
  defp bounded_list?([_ | tail], n) when n > 0, do: bounded_list?(tail, n - 1)
  defp bounded_list?(_, _), do: false
end

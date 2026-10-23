defmodule OperatorViewWeb.OperatorLive do
  @moduledoc """
  The single read-only observer page.

  Browser input can only choose an allowlisted instance (the `instance` URL
  parameter or the `select` event) and ask for a refresh. Every read is one of
  `OperatorView.Reader`'s fixed operations. Reads run in at most one refresh
  worker per page, so the page stays responsive while a read is slow.

  Connecting, reconnecting, selecting and pressing Refresh read a full,
  authoritative snapshot. After each refresh the page polls status and
  summaries once per interval. A failed or stalled read keeps the previous
  data labelled stale and pauses polling until the operator refreshes. A reply
  from a previous selection is discarded.
  """

  use Phoenix.LiveView

  alias OperatorView.{Observation, Settings}

  @impl true
  def mount(_params, _session, socket) do
    settings = Settings.fetch!()

    socket =
      socket
      |> assign(settings: settings, allowed: settings.instances, selected: nil)
      |> assign(generation: 0, observation: Observation.new(), rejected: false)
      |> assign(refresh: nil, queued: nil, timer: nil, paused: false)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    case Map.get(params, "instance") do
      nil -> {:noreply, select(socket, hd(socket.assigns.allowed))}
      name when is_binary(name) -> {:noreply, select_allowed(socket, name)}
      _other -> {:noreply, assign(socket, :rejected, true)}
    end
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    {:noreply, socket |> assign(:paused, false) |> request(:full)}
  end

  def handle_event("select", %{"instance" => name}, socket) when is_binary(name) do
    if name in socket.assigns.allowed do
      {:noreply, push_patch(socket, to: "/?" <> URI.encode_query(%{"instance" => name}))}
    else
      {:noreply, assign(socket, :rejected, true)}
    end
  end

  # Any other event, including one sent by a modified client, changes nothing.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info({ref, reads}, %{assigns: %{refresh: %{task: %{ref: ref}}}} = socket) do
    Process.demonitor(ref, [:flush])
    {:noreply, finish(socket, {:reads, reads})}
  end

  def handle_info({:refresh_deadline, ref}, socket) do
    case socket.assigns.refresh do
      %{task: %{ref: ^ref} = task} ->
        case Task.shutdown(task, :brutal_kill) do
          {:ok, reads} -> {:noreply, finish(socket, {:reads, reads})}
          _stopped -> {:noreply, finish(socket, {:failed, :timeout})}
        end

      _other ->
        {:noreply, socket}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, socket) do
    case socket.assigns.refresh do
      %{task: %{ref: ^ref}} -> {:noreply, finish(socket, {:failed, :read_failed})}
      _other -> {:noreply, socket}
    end
  end

  def handle_info({:poll, token}, %{assigns: %{timer: {_timer, token}}} = socket) do
    socket = assign(socket, :timer, nil)

    if socket.assigns.paused do
      {:noreply, socket}
    else
      {:noreply, request(socket, :poll)}
    end
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  # Killing a refresh worker never orphans a release rpc process: the release
  # transport's guard stops the rpc process tree when its caller stops. The
  # deadline handler above relies on the same guarantee.
  @impl true
  def terminate(_reason, socket) do
    case socket.assigns[:refresh] do
      %{task: task} -> Task.shutdown(task, :brutal_kill)
      _none -> :ok
    end

    :ok
  end

  defp select_allowed(socket, name) do
    if name in socket.assigns.allowed do
      socket |> assign(:rejected, false) |> select(name)
    else
      assign(socket, :rejected, true)
    end
  end

  defp select(%{assigns: %{selected: name}} = socket, name), do: socket

  defp select(socket, name) do
    %{generation: generation, observation: observation} = socket.assigns

    socket
    |> cancel_timer()
    |> assign(selected: name, generation: generation + 1, paused: false)
    |> assign(:observation, Observation.for_selection(observation))
    |> request(:full)
  end

  # The disconnected HTTP render reads nothing; the connected mount reads.
  defp request(socket, kind) do
    cond do
      not connected?(socket) -> socket
      socket.assigns.refresh -> queue(socket, kind)
      true -> start_refresh(socket, kind)
    end
  end

  # A queued full refresh (manual or selection) is never downgraded to a poll.
  defp queue(%{assigns: %{queued: :full}} = socket, _kind), do: socket
  defp queue(socket, kind), do: assign(socket, :queued, kind)

  defp start_refresh(socket, kind) do
    %{settings: settings, selected: instance, generation: generation} = socket.assigns
    socket = cancel_timer(socket)
    args = [kind, instance, settings]
    task = Task.Supervisor.async(OperatorView.TaskSupervisor, Observation, :read, args)
    message = {:refresh_deadline, task.ref}
    deadline = Process.send_after(self(), message, settings.refresh_deadline_ms)

    refresh = %{
      task: task,
      kind: kind,
      instance: instance,
      generation: generation,
      deadline: deadline
    }

    assign(socket, :refresh, refresh)
  end

  defp finish(socket, outcome) do
    %{refresh: refresh, generation: generation} = socket.assigns
    Process.cancel_timer(refresh.deadline)
    socket = assign(socket, :refresh, nil)

    socket =
      if refresh.generation == generation do
        record(socket, refresh, outcome)
      else
        socket
      end

    continue(socket)
  end

  defp record(socket, _refresh, {:reads, reads}) do
    observation = Observation.merge_reads(socket.assigns.observation, reads)
    assign(socket, observation: observation, paused: Observation.pause?(reads))
  end

  # A stalled refresh: retry only when the operator asks.
  defp record(socket, refresh, {:failed, code}) do
    observation =
      Observation.fail(socket.assigns.observation, refresh.kind, refresh.instance, code)

    assign(socket, observation: observation, paused: true, queued: nil)
  end

  defp continue(%{assigns: %{queued: :full}} = socket) do
    socket |> assign(:queued, nil) |> start_refresh(:full)
  end

  defp continue(%{assigns: %{queued: :poll, paused: false}} = socket) do
    socket |> assign(:queued, nil) |> start_refresh(:poll)
  end

  defp continue(socket), do: socket |> assign(:queued, nil) |> schedule_poll()

  defp schedule_poll(%{assigns: %{paused: true}} = socket), do: socket
  defp schedule_poll(%{assigns: %{selected: nil}} = socket), do: socket

  defp schedule_poll(socket) do
    socket = cancel_timer(socket)
    token = make_ref()
    interval = socket.assigns.settings.refresh_interval_ms
    timer = Process.send_after(self(), {:poll, token}, interval)
    assign(socket, :timer, {timer, token})
  end

  defp cancel_timer(%{assigns: %{timer: {timer, _token}}} = socket) do
    Process.cancel_timer(timer)
    assign(socket, :timer, nil)
  end

  defp cancel_timer(socket), do: socket

  @impl true
  def render(assigns) do
    ~H"""
    <main class="operator">
      <header>
        <h1>gen_agent_server operator view</h1>
        <p class="note">
          Read-only observer for one running release. It cannot submit, cancel or change work.
        </p>
      </header>

      <section class="controls">
        <form id="select-instance" phx-change="select">
          <label for="instance">Instance</label>
          <select id="instance" name="instance">
            <option :for={name <- @allowed} value={name} selected={name == @selected}>{name}</option>
          </select>
        </form>
        <button id="refresh" type="button" phx-click="refresh">Refresh</button>
        <span :if={@refresh} class="busy">Reading the release...</span>
      </section>

      <p :if={@rejected} id="rejected" class="error">
        That instance is not in this observer's allowlist. Nothing was read for it.
      </p>
      <p :if={@paused} id="paused" class="warning">
        Automatic refresh is paused after a failed read. Use Refresh to read again.
      </p>

      <section id="instances">
        <h2>Allowlisted instances</h2>
        <.read_state section={@observation.instances} />
        <ul>
          <li
            :for={{name, state} <- Observation.instance_states(@allowed, @observation.instances)}
            data-instance={name}
            data-state={Atom.to_string(state)}
          >
            {name}: {instance_label(state)}
          </li>
        </ul>
      </section>

      <section :if={@selected} id="description">
        <h2>Routes and limits of {@selected}</h2>
        <.read_state section={@observation.description} />
        <.description
          :if={data(@observation.description)}
          data={data(@observation.description)}
        />
      </section>

      <section :if={@selected} id="status">
        <h2>Runtime status of {@selected}</h2>
        <.read_state section={@observation.status} />
        <.status_fields :if={data(@observation.status)} data={data(@observation.status)} />
      </section>

      <section :if={@selected} id="invocations">
        <h2>Up to 50 retained invocations</h2>
        <p class="note">
          Content-free summaries the release still retains, newest admission first. Row counts
          are not totals: eviction and instance restarts remove entries. Terminal times are the
          release's observation of completion, not the provider's finish time.
        </p>
        <.read_state section={@observation.invocations} />
        <p :if={data(@observation.invocations) == []} id="no-invocations">
          No retained invocations. This does not show that earlier work completed.
        </p>
        <table :if={data(@observation.invocations) not in [nil, []]}>
          <thead>
            <tr>
              <th>ID</th>
              <th>Route</th>
              <th>Source</th>
              <th>Status</th>
              <th>Admitted</th>
              <th>Completed</th>
              <th>Duration</th>
              <th>Error category</th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={entry <- data(@observation.invocations)}
              data-id={show(entry.id)}
              data-status={show(entry.status)}
            >
              <td>{show(entry.id)}</td>
              <td>{show(entry.route)}</td>
              <td>{show(entry.source)}</td>
              <td>{show(entry.status)}</td>
              <td>{time(entry.admitted_at_unix_ms)}</td>
              <td>{time(entry.completed_at_unix_ms)}</td>
              <td>{duration(entry)}</td>
              <td>{category(entry.error_category)}</td>
            </tr>
          </tbody>
        </table>
      </section>
    </main>
    """
  end

  defp read_state(assigns) do
    ~H"""
    <p class="read-state" data-stale={to_string(stale?(@section))}>{read_state_text(@section)}</p>
    """
  end

  defp description(assigns) do
    ~H"""
    <dl>
      <dt>Created through create_instance</dt>
      <dd>{show(@data.configured)}</dd>
      <dt>Strategy</dt>
      <dd>{show(@data.strategy)}</dd>
      <dt>max_in_flight</dt>
      <dd>{show(@data.max_in_flight)}</dd>
      <dt>max_results</dt>
      <dd>{show(@data.max_results)}</dd>
    </dl>
    <p :if={@data.configured == false} class="note">
      The release reports route names only for this instance; other route settings are unknown.
    </p>
    <p :if={@data.routes == :unknown}>Routes: unknown</p>
    <table :if={is_list(@data.routes)}>
      <thead>
        <tr>
          <th>Route</th>
          <th>Provider</th>
          <th>Model</th>
          <th>Effort</th>
          <th>Access</th>
          <th>Response text</th>
        </tr>
      </thead>
      <tbody>
        <tr :for={route <- @data.routes}>
          <td>{show(route.name)}</td>
          <td data-route-field="provider">{show(route.provider)}</td>
          <td>{show(route.model)}</td>
          <td>{show(route.effort)}</td>
          <td>{show(route.access)}</td>
          <td>{show(route.response_text)}</td>
        </tr>
      </tbody>
    </table>
    """
  end

  defp status_fields(assigns) do
    ~H"""
    <dl>
      <dt>Strategy</dt>
      <dd>{show(@data.strategy)}</dd>
      <dt>In flight</dt>
      <dd data-field="in_flight">{show(@data.in_flight)}</dd>
      <dt>Pending tokens</dt>
      <dd data-field="pending">{show(@data.pending)}</dd>
      <dt>External routes</dt>
      <dd>{names(@data.routes)}</dd>
      <dt>Internal agents</dt>
      <dd>{names(@data.agents)}</dd>
      <dt>Other status fields (names only, not interpreted)</dt>
      <dd data-field="other">{names(@data.other_fields)}</dd>
    </dl>
    <p class="note">Runtime state reported by the release. It is not provider health.</p>
    """
  end

  defp data(nil), do: nil
  defp data(%{data: data}), do: data

  defp stale?(%{stale: stale}), do: stale
  defp stale?(_section), do: false

  defp read_state_text(nil), do: "Not read yet."
  defp read_state_text(%{error: nil, read_at: at}), do: "Read at #{time(at)}."

  defp read_state_text(%{error: :instance_not_found, read_at: at}) do
    "Instance not running in the release (checked #{time(at)}); nothing is retained for it."
  end

  defp read_state_text(%{error: code, stale: true, read_at: at}) do
    "Stale: showing data read at #{time(at)}. Latest read failed: #{error_label(code)}."
  end

  defp read_state_text(%{error: code}), do: "Latest read failed: #{error_label(code)}. No data."

  defp error_label(:timeout), do: "release read timed out"
  defp error_label(:release_unavailable), do: "release unavailable"
  defp error_label(:bad_output), do: "unreadable release output"
  defp error_label(_code), do: "read failed"

  defp instance_label(:running), do: "running in the release"
  defp instance_label(:not_running), do: "not running in the release"
  defp instance_label(:unknown), do: "unknown"

  defp show(:unknown), do: "unknown"
  defp show(:not_set), do: "not set"
  defp show(true), do: "yes"
  defp show(false), do: "no"
  defp show(nil), do: "n/a"
  defp show(value) when is_integer(value), do: Integer.to_string(value)
  defp show(value) when is_binary(value), do: value
  defp show(_value), do: "unknown"

  defp names(list) when is_list(list) and list != [], do: Enum.join(list, ", ")
  defp names([]), do: "none"
  defp names(_value), do: "unknown"

  defp time(nil), do: "n/a"

  defp time(ms) when is_integer(ms) do
    case DateTime.from_unix(ms, :millisecond) do
      {:ok, datetime} -> DateTime.to_iso8601(datetime)
      {:error, _reason} -> "unknown"
    end
  end

  defp time(_value), do: "unknown"

  defp duration(%{status: "pending", duration_ms: nil}), do: "n/a (pending)"
  defp duration(%{duration_ms: ms}) when is_integer(ms), do: "#{ms} ms"
  defp duration(%{duration_ms: nil}), do: "n/a"
  defp duration(_entry), do: "unknown"

  defp category(nil), do: "none"
  defp category(value), do: show(value)
end

defmodule OperatorView.Observation do
  @moduledoc """
  What one observer page knows about the release, section by section.

  Each section is `nil` until its first read, then a map with the last
  successful `data`, its `read_at` (Unix milliseconds), the latest `error` code
  and `stale`. Sections are separate reads, not an atomic snapshot, so each
  keeps its own read time.

  A failed read keeps the previous data and marks it stale. A missing instance
  clears that section, because the release no longer retains anything for it.
  A refresh stops at its first transport failure; its remaining sections are
  recorded as skipped instead of sending more reads to a failing release.
  """

  alias OperatorView.Reader

  defstruct instances: nil, description: nil, status: nil, invocations: nil

  @transport_errors [:timeout, :release_unavailable, :bad_output, :read_failed]

  def new, do: %__MODULE__{}

  @doc "Keep the instance list and drop data that belonged to the previous selection."
  def for_selection(%__MODULE__{instances: instances}), do: %__MODULE__{instances: instances}

  @doc "Sections read by a `:full` refresh (connect, selection, manual) or a `:poll`."
  def sections(:full, nil), do: [:instances]
  def sections(:full, _instance), do: [:instances, :description, :status, :invocations]
  def sections(:poll, nil), do: []
  def sections(:poll, _instance), do: [:status, :invocations]

  @doc "Run the reads of one refresh. Called in the page's refresh worker."
  def read(kind, instance, settings) do
    {reads, _failure} =
      kind
      |> sections(instance)
      |> Enum.reduce({%{}, nil}, &read_section(&1, &2, instance, settings))

    reads
  end

  defp read_section(section, {reads, nil}, instance, settings) do
    outcome =
      case read_one(section, instance, settings) do
        {:ok, data} -> {:ok, data, now()}
        {:error, code} -> {:error, code, now()}
      end

    failure = if interrupts?(outcome), do: elem(outcome, 1)
    {Map.put(reads, section, outcome), failure}
  end

  defp read_section(section, {reads, failure}, _instance, _settings) do
    {Map.put(reads, section, {:skipped, failure}), failure}
  end

  defp read_one(section, instance, %{transport: transport, rpc_timeout_ms: timeout} = settings) do
    case section do
      :instances -> Reader.instances(transport, settings.instances, timeout)
      :description -> Reader.describe(transport, instance, timeout)
      :status -> Reader.status(transport, instance, timeout)
      :invocations -> Reader.invocations(transport, instance, timeout)
    end
  end

  @doc "Merge the outcomes of one refresh into the observation."
  def merge_reads(%__MODULE__{} = observation, reads) when is_map(reads) do
    Enum.reduce(reads, observation, fn {section, outcome}, acc ->
      Map.update!(acc, section, &merge(&1, outcome))
    end)
  end

  @doc "Record a refresh that returned nothing, for example one stopped at its deadline."
  def fail(observation, kind, instance, code) do
    reads = Map.new(sections(kind, instance), &{&1, {:skipped, code}})
    merge_reads(observation, reads)
  end

  @doc "Whether automatic refresh should pause after these outcomes."
  def pause?(reads), do: Enum.any?(Map.values(reads), &interrupts?/1)

  @doc "Each allowlisted name with `:running`, `:not_running` or `:unknown`."
  def instance_states(allowed, section) do
    running = current(section)
    Enum.map(allowed, &{&1, state_of(&1, running)})
  end

  defp current(%{data: data, error: nil}) when is_list(data), do: data
  defp current(_section), do: nil

  defp state_of(_name, nil), do: :unknown
  defp state_of(name, running), do: if(name in running, do: :running, else: :not_running)

  defp merge(_previous, {:ok, data, at}) do
    %{data: data, read_at: at, error: nil, stale: false}
  end

  defp merge(_previous, {:error, :instance_not_found, at}) do
    %{data: nil, read_at: at, error: :instance_not_found, stale: false}
  end

  defp merge(previous, {:error, code, _at}), do: keep_stale(previous, code)
  defp merge(previous, {:skipped, code}), do: keep_stale(previous, code)

  defp keep_stale(nil, code), do: %{data: nil, read_at: nil, error: code, stale: false}
  defp keep_stale(previous, code), do: %{previous | error: code, stale: previous.data != nil}

  defp interrupts?({:error, code, _at}), do: code in @transport_errors
  defp interrupts?({:skipped, _code}), do: true
  defp interrupts?(_outcome), do: false

  defp now, do: System.system_time(:millisecond)
end

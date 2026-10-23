defmodule OperatorView.Reader do
  @moduledoc """
  The fixed set of read-only release operations the observer performs.

  Operation names are constants here: `instances`, `describe_instance`,
  `status` and `invocations`. Scoped reads always pass an explicit,
  allowlisted instance, because Ops otherwise defaults an omitted instance to
  the release's default instance. Summaries always request `limit: 50`.

  Results are projected to display data. Missing or unrecognized values become
  `:unknown` (and an explicit JSON `null` becomes `:not_set`) rather than being
  guessed. Errors are reduced to a fixed code, so release output, paths and
  error messages never reach the page.
  """

  @operations ~w(instances describe_instance status invocations)
  @summary_limit 50
  @max_text 200
  @max_entries 64
  @statuses ~w(pending completed failed cancelled)
  @sources ~w(api local_cli remote_cli scheduler mcp)
  @error_categories ~w(timeout task_crashed backend_error cancelled)
  @status_fields ~w(strategy routes agents in_flight pending)

  @doc "The only operation names this module sends."
  def operations, do: @operations

  @doc "The fixed summary limit."
  def summary_limit, do: @summary_limit

  @doc """
  The names in `allowed` that are running in the release, in `allowed` order.

  Membership is checked against the whole release response before anything is
  bounded, so an allowlisted name is never reported absent because the release
  listed many other instances first.
  """
  def instances(transport, allowed, timeout_ms) when is_list(allowed) do
    with {:ok, data} <- call(transport, "instances", %{}, timeout_ms) do
      case data do
        %{"instances" => names} when is_list(names) -> running(names, allowed)
        _other -> {:error, :bad_output}
      end
    end
  end

  @doc "Routes, strategy and limits of one instance."
  def describe(transport, instance, timeout_ms) do
    with {:ok, data} <- scoped(transport, "describe_instance", instance, timeout_ms) do
      project(data, &description/1)
    end
  end

  @doc "Runtime status of one instance. Strategy-specific fields are not interpreted."
  def status(transport, instance, timeout_ms) do
    with {:ok, data} <- scoped(transport, "status", instance, timeout_ms) do
      project(data, &status_data/1)
    end
  end

  @doc "Up to 50 retained, content-free invocation summaries, newest admission first."
  def invocations(transport, instance, timeout_ms) when is_binary(instance) do
    args = %{"instance" => instance, "limit" => @summary_limit}

    with {:ok, data} <- call(transport, "invocations", args, timeout_ms) do
      case data do
        %{"invocations" => entries} when is_list(entries) -> summaries(entries)
        _other -> {:error, :bad_output}
      end
    end
  end

  defp scoped(transport, operation, instance, timeout_ms) when is_binary(instance) do
    call(transport, operation, %{"instance" => instance}, timeout_ms)
  end

  defp call(transport, operation, args, timeout_ms) when operation in @operations do
    case transport.call(operation, args, timeout_ms) do
      {:ok, data} -> {:ok, data}
      {:error, error} -> {:error, classify(error)}
      _other -> {:error, :bad_output}
    end
  catch
    _kind, _reason -> {:error, :read_failed}
  end

  defp classify(error) when is_map(error) do
    case Map.get(error, "code", Map.get(error, :code)) do
      "rpc_timeout" -> :timeout
      "rpc_failed" -> :release_unavailable
      "release_unavailable" -> :release_unavailable
      "rpc_bad_output" -> :bad_output
      "instance_not_found" -> :instance_not_found
      _other -> :read_failed
    end
  end

  defp classify(_error), do: :read_failed

  defp project(data, fun) when is_map(data), do: {:ok, fun.(data)}
  defp project(_data, _fun), do: {:error, :bad_output}

  defp description(data) do
    limits = if is_map(data["limits"]), do: data["limits"], else: %{}

    %{
      configured: if(is_boolean(data["configured"]), do: data["configured"], else: :unknown),
      strategy: text(data["strategy"]),
      max_in_flight: count(limits["max_in_flight"]),
      max_results: count(limits["max_results"]),
      routes: routes(data["routes"])
    }
  end

  defp routes(routes) when is_list(routes) do
    routes |> Enum.take(@max_entries) |> Enum.map(&route/1)
  end

  defp routes(_routes), do: :unknown

  defp route(route) when is_map(route) do
    %{
      name: text(route["name"]),
      provider: field(route, "provider"),
      model: field(route, "model"),
      effort: field(route, "effort"),
      access: access(route),
      response_text: field(route, "codex_response_text")
    }
  end

  defp route(_route) do
    %{
      name: :unknown,
      provider: :unknown,
      model: :unknown,
      effort: :unknown,
      access: :unknown,
      response_text: :unknown
    }
  end

  defp access(route) do
    cond do
      Map.has_key?(route, "claude_permission_mode") -> field(route, "claude_permission_mode")
      Map.has_key?(route, "codex_sandbox") -> field(route, "codex_sandbox")
      true -> :unknown
    end
  end

  defp status_data(data) do
    %{
      strategy: text(data["strategy"]),
      routes: names(data["routes"]),
      agents: names(data["agents"]),
      in_flight: size(data["in_flight"]),
      pending: size(data["pending"]),
      other_fields: other_fields(data)
    }
  end

  # Only field names are shown for strategy-specific status, never their values.
  defp other_fields(data) do
    data
    |> Map.keys()
    |> Enum.filter(&is_binary/1)
    |> Enum.reject(&(&1 in @status_fields))
    |> Enum.sort()
    |> Enum.take(16)
    |> Enum.map(&truncate/1)
  end

  defp summaries(entries) do
    if Enum.all?(entries, &is_map/1) do
      {:ok, entries |> Enum.take(@summary_limit) |> Enum.map(&summary/1)}
    else
      {:error, :bad_output}
    end
  end

  defp summary(entry) do
    %{
      id: text(entry["id"]),
      route: text(entry["route"]),
      source: member(entry["source"], @sources),
      status: member(entry["status"], @statuses),
      admitted_at_unix_ms: optional_count(entry["admitted_at_unix_ms"]),
      completed_at_unix_ms: optional_count(entry["completed_at_unix_ms"]),
      duration_ms: optional_count(entry["duration_ms"]),
      error_category: category(entry["error_category"])
    }
  end

  defp running(names, allowed) do
    if Enum.all?(names, &is_binary/1) do
      present = MapSet.new(names)
      {:ok, Enum.filter(allowed, &MapSet.member?(present, &1))}
    else
      {:error, :bad_output}
    end
  end

  defp string_list(values) do
    if Enum.all?(values, &is_binary/1) do
      {:ok, values |> Enum.take(@max_entries) |> Enum.map(&truncate/1)}
    else
      {:error, :bad_output}
    end
  end

  defp names(values) when is_list(values) do
    case string_list(values) do
      {:ok, names} -> names
      {:error, _reason} -> :unknown
    end
  end

  defp names(_values), do: :unknown

  defp field(map, key) do
    case Map.fetch(map, key) do
      {:ok, nil} -> :not_set
      {:ok, value} when is_binary(value) -> truncate(value)
      {:ok, _value} -> :unknown
      :error -> :unknown
    end
  end

  defp text(value) when is_binary(value), do: truncate(value)
  defp text(_value), do: :unknown

  defp count(value) when is_integer(value) and value >= 0, do: value
  defp count(_value), do: :unknown

  defp optional_count(nil), do: nil
  defp optional_count(value), do: count(value)

  defp size(value) when is_integer(value) and value >= 0, do: value
  defp size(value) when is_list(value), do: length(value)
  defp size(value) when is_map(value), do: map_size(value)
  defp size(_value), do: :unknown

  defp member(value, allowed) when is_binary(value) do
    if value in allowed, do: value, else: :unknown
  end

  defp member(_value, _allowed), do: :unknown

  defp category(nil), do: nil
  defp category(value), do: member(value, @error_categories)

  defp truncate(value), do: String.slice(value, 0, @max_text)
end

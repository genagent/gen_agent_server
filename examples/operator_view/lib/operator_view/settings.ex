defmodule OperatorView.Settings do
  @moduledoc """
  Observer settings from the `:operator_view` application environment.

  The instance allowlist, transport and timeouts are fixed by the operator at
  startup. Browser input can only choose among the allowlisted names. The
  operator token and the release path are read where they are used and are
  never copied into page state.
  """

  defstruct [:instances, :transport, :rpc_timeout_ms, :refresh_interval_ms, :refresh_deadline_ms]

  @max_instances 16
  @min_token_bytes 24

  @doc "Read and validate the current settings. Raises `ArgumentError` when invalid."
  def fetch! do
    env = Application.get_all_env(:operator_view)
    validate_token!(Keyword.get(env, :token))
    rpc_timeout_ms = positive!(env, :rpc_timeout_ms, 5_000)

    %__MODULE__{
      instances: instances!(Keyword.get(env, :instances)),
      transport: transport!(Keyword.get(env, :transport, OperatorView.Transport.Release)),
      rpc_timeout_ms: rpc_timeout_ms,
      refresh_interval_ms: positive!(env, :refresh_interval_ms, 5_000),
      refresh_deadline_ms: positive!(env, :refresh_deadline_ms, 4 * rpc_timeout_ms + 1_000)
    }
  end

  defp validate_token!(token) do
    if is_binary(token) and byte_size(token) >= @min_token_bytes do
      :ok
    else
      raise ArgumentError, "OPERATOR_VIEW_TOKEN must be at least #{@min_token_bytes} bytes"
    end
  end

  defp instances!(names) when is_list(names) and names != [] do
    cond do
      length(names) > @max_instances ->
        raise ArgumentError, "OPERATOR_VIEW_INSTANCES accepts at most #{@max_instances} names"

      length(names) != length(Enum.uniq(names)) ->
        raise ArgumentError, "OPERATOR_VIEW_INSTANCES contains duplicate names"

      not Enum.all?(names, &valid_instance_name?/1) ->
        raise ArgumentError, "OPERATOR_VIEW_INSTANCES contains an invalid instance name"

      true ->
        names
    end
  end

  defp instances!(_names) do
    raise ArgumentError, "OPERATOR_VIEW_INSTANCES must name at least one instance"
  end

  # Server instance names, including the default `server/default`.
  defp valid_instance_name?(name) do
    is_binary(name) and String.match?(name, ~r/\A[A-Za-z0-9][A-Za-z0-9._\/-]{0,127}\z/)
  end

  defp positive!(env, key, default) do
    case Keyword.get(env, key, default) do
      value when is_integer(value) and value > 0 -> value
      _other -> raise ArgumentError, "#{key} must be a positive number of milliseconds"
    end
  end

  defp transport!(module) when is_atom(module) and not is_nil(module), do: module
  defp transport!(_module), do: raise(ArgumentError, "transport must be a module")
end

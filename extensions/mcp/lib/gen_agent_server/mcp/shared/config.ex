defmodule GenAgentServer.MCP.Shared.Config do
  @moduledoc false
  @prefix "GEN_AGENT_SERVER_SHARED_MCP_"
  @keys ~w(ENABLED PORT TOKEN INSTANCES)

  # Mix tasks, tests, and short-lived local commands start the OTP application
  # too. Only a packaged release owns the shared listener.
  def from_release_env!(env \\ System.get_env()) do
    if Map.has_key?(env, "RELEASE_ROOT"), do: from_env!(env), else: nil
  end

  # Only a digest enters application configuration or listener process state.
  def from_env!(env \\ System.get_env()) do
    values = Map.new(@keys, &{&1, env[@prefix <> &1]})

    case values["ENABLED"] do
      "true" ->
        port =
          case Integer.parse(values["PORT"] || "") do
            {port, ""} when port in 1..65_535 -> port
            _ -> invalid!("PORT must be an integer from 1 to 65535")
          end

        token = values["TOKEN"] || ""

        unless Regex.match?(~r/\A[A-Za-z0-9_-]{32,256}\z/, token),
          do: invalid!("TOKEN must contain 32..256 URL-safe ASCII characters")

        instances =
          case Jason.decode(values["INSTANCES"] || "") do
            {:ok, names} when is_list(names) -> names
            _ -> invalid!("INSTANCES must be a JSON array of names")
          end

        unless length(instances) in 1..64 and
                 Enum.all?(instances, &(is_binary(&1) and byte_size(&1) in 1..256)) and
                 length(Enum.uniq(instances)) == length(instances),
               do: invalid!("INSTANCES must contain 1..64 distinct nonempty names")

        %{port: port, token_hash: :crypto.hash(:sha256, token), instances: instances}

      disabled when disabled in [nil, "false"] ->
        if Enum.any?(~w(PORT TOKEN INSTANCES), &(values[&1] != nil)),
          do: invalid!("set ENABLED=true before configuring the listener")

        nil

      _ ->
        invalid!("ENABLED must be true or false")
    end
  end

  def validate_scope!(nil, _configured), do: :ok

  def validate_scope!(%{instances: names}, configured) do
    unless Enum.all?(names, &Map.has_key?(configured, &1)),
      do: invalid!("INSTANCES must name only startup-configured instances")

    :ok
  end

  defp invalid!(message), do: raise(ArgumentError, @prefix <> message)
end

defmodule GenAgentServer.Jobs do
  @moduledoc "Validates opt-in Quantum jobs from the server configuration file."

  def load!(nil, _instances), do: []

  def load!(path, instances) when is_binary(path) and is_map(instances) do
    path = Path.expand(path)
    document = path |> File.read!() |> Jason.decode!()

    entries =
      case document do
        %{"jobs" => jobs} when is_list(jobs) -> jobs
        %{} = object when not is_map_key(object, "jobs") -> []
        _ -> raise ArgumentError, "#{path} jobs must be an array"
      end

    jobs = Enum.map(entries, &parse!(&1, path, instances))
    names = Enum.map(jobs, & &1.name)

    if length(names) != length(Enum.uniq(names)) do
      raise ArgumentError, "#{path} contains duplicate job names"
    end

    jobs
  end

  defp parse!(
         %{"name" => name, "instance" => instance, "agent" => agent, "schedule" => schedule} =
           entry,
         path,
         instances
       )
       when is_binary(name) and is_binary(instance) and is_binary(agent) and
              is_binary(schedule) do
    unless name != "" and String.match?(name, ~r/\A[a-zA-Z0-9_-]+\z/) do
      raise ArgumentError, "job name must contain only letters, numbers, underscore, or dash"
    end

    unless agent in Map.get(instances, instance, []) do
      raise ArgumentError, "job #{name} references unknown instance or agent"
    end

    prompt_source =
      case {Map.fetch(entry, "prompt"), Map.fetch(entry, "prompt_file")} do
        {{:ok, prompt}, :error} when is_binary(prompt) and prompt != "" ->
          {:literal, prompt}

        {:error, {:ok, file}} when is_binary(file) and file != "" ->
          file = Path.expand(file, Path.dirname(path))

          unless File.regular?(file) do
            raise ArgumentError, "job #{name} prompt_file does not exist: #{file}"
          end

          {:file, file}

        _ ->
          raise ArgumentError, "job #{name} needs exactly one non-empty prompt or prompt_file"
      end

    overlap = Map.get(entry, "overlap", false)

    unless is_boolean(overlap) do
      raise ArgumentError, "job #{name} overlap must be a boolean"
    end

    parsed_schedule =
      try do
        Quantum.Normalizer.normalize_schedule(schedule)
      rescue
        error in RuntimeError ->
          raise ArgumentError,
                "#{path}: job #{name} has invalid schedule #{inspect(schedule)}: #{Exception.message(error)}"
      end

    %{
      name: name,
      instance: instance,
      agent: agent,
      schedule: parsed_schedule,
      prompt_source: prompt_source,
      overlap: overlap
    }
  end

  defp parse!(_entry, _path, _instances) do
    raise ArgumentError, "each job needs a name, instance, agent, and schedule"
  end
end

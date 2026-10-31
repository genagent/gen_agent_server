defmodule GenAgentServer.Selection do
  @moduledoc """
  Optional, pure recommendations over caller-approved named routes for new tasks.

  `suggest/3` and `explain/3` return the same explained outcome. All input maps
  use string keys; identifiers and capabilities are non-empty strings. No client
  string is converted to an atom. Unknown fields (including prompts, roles,
  profiles and session/continuation fields) are rejected, not interpreted as policy.

  Descriptor: required `required_capabilities` (list), optional `route`,
  `provider`, `model`, `effort` and `preferred_provider` (strings).
  Catalogue: required `revision` (string) and `candidates` (list). Each candidate
  requires a unique `route`, `provider`, `model`, `effort`, `capabilities` and
  `availability`. Model and effort are configured strings or nil (unknown);
  capabilities are operator attestations, not inferred provider properties.
  Availability is `"available"`, `"unavailable"` or `"unknown"`, supplied by the
  caller and never measured here.
  Policy: required `revision` and `catalogue_revision` (strings), optional
  `unknown_availability` (`"exclude"`, the default, or `"allow"`).

  Explicit selections are hard constraints, followed by required capabilities
  and availability eligibility. Preference only ranks eligible candidates;
  ties use ascending route name, independent of catalogue order. Revisions are
  caller labels, not verified source fingerprints. A policy/catalogue revision
  mismatch fails before selection.

  Success is `{:ok, explanation}`. No eligible route is
  `{:error, %{code: :no_route, explanation: explanation}}`; malformed inputs and
  revision conflicts return typed error maps. Explanations include the configured
  recommendation, eligible alternative route names, fixed exclusion codes,
  revisions and ordering rules. Result size is proportional to the caller's
  catalogue; no output-size cap is enforced. They never report actual execution settings.

  This helper reads no application state, health, capacity or installed models,
  and starts no work. Suggestions reserve nothing and do not authorize admission.
  The caller retains final choice, admission and actual provider reporting.
  Continuations must stay with their admitted selection outside this helper.
  """

  @descriptor_fields ~w(required_capabilities route provider model effort preferred_provider)
  @candidate_fields ~w(route provider model effort capabilities availability)
  @policy_fields ~w(revision catalogue_revision unknown_availability)
  @rules [
    :explicit_constraints,
    :required_capabilities,
    :availability,
    :preferred_provider,
    :route_name
  ]

  @type outcome :: {:ok, map()} | {:error, map()}

  @doc "Recommend an eligible configured route without reserving or admitting work."
  @spec suggest(map(), map(), map()) :: outcome()
  def suggest(descriptor, catalogue, policy) do
    with :ok <- validate_descriptor(descriptor),
         :ok <- validate_catalogue(catalogue),
         :ok <- validate_policy(policy),
         :ok <- match_revision(catalogue, policy) do
      select(descriptor, catalogue, policy)
    end
  end

  @doc "Returns the same deterministic, explained outcome as `suggest/3`."
  @spec explain(map(), map(), map()) :: outcome()
  def explain(descriptor, catalogue, policy), do: suggest(descriptor, catalogue, policy)

  defp validate_descriptor(value) do
    with :ok <- fields(value, @descriptor_fields, :descriptor),
         true <- strings?(Map.get(value, "required_capabilities")),
         true <-
           Enum.all?(~w(route provider model effort preferred_provider), fn key ->
             not Map.has_key?(value, key) or identifier?(value[key])
           end) do
      :ok
    else
      false -> invalid(:descriptor)
      error -> error
    end
  end

  defp validate_catalogue(value) do
    with :ok <- fields(value, ~w(revision candidates), :catalogue),
         true <- identifier?(value["revision"]) and proper_list?(value["candidates"]),
         :ok <- validate_candidates(value["candidates"]) do
      names = Enum.map(value["candidates"], & &1["route"])

      if length(names) == length(Enum.uniq(names)),
        do: :ok,
        else: {:error, %{code: :duplicate_route, input: :catalogue}}
    else
      false -> invalid(:catalogue)
      error -> error
    end
  end

  defp validate_candidates(candidates) do
    Enum.reduce_while(candidates, :ok, fn candidate, :ok ->
      case validate_candidate(candidate) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_candidate(value) do
    with :ok <- fields(value, @candidate_fields, :candidate),
         true <- Enum.all?(@candidate_fields, &Map.has_key?(value, &1)),
         true <- identifier?(value["route"]) and identifier?(value["provider"]),
         true <- Enum.all?(~w(model effort), &(is_nil(value[&1]) or identifier?(value[&1]))),
         true <- strings?(value["capabilities"]),
         true <- value["availability"] in ~w(available unavailable unknown) do
      :ok
    else
      false -> invalid(:candidate)
      error -> error
    end
  end

  defp validate_policy(value) do
    with :ok <- fields(value, @policy_fields, :policy),
         true <- identifier?(value["revision"]) and identifier?(value["catalogue_revision"]),
         true <- Map.get(value, "unknown_availability", "exclude") in ~w(exclude allow) do
      :ok
    else
      false -> invalid(:policy)
      error -> error
    end
  end

  defp fields(value, allowed, input) when is_map(value) and not is_struct(value) do
    if Enum.all?(Map.keys(value), &(&1 in allowed)),
      do: :ok,
      else: {:error, %{code: :unsupported_fields, input: input}}
  end

  defp fields(_, _, input), do: invalid(input)
  defp invalid(input), do: {:error, %{code: :invalid_input, input: input}}
  defp identifier?(value), do: is_binary(value) and byte_size(value) > 0
  defp strings?([]), do: true
  defp strings?([head | tail]), do: identifier?(head) and strings?(tail)
  defp strings?(_), do: false
  defp proper_list?([]), do: true
  defp proper_list?([_ | tail]), do: proper_list?(tail)
  defp proper_list?(_), do: false

  defp match_revision(catalogue, policy) do
    if catalogue["revision"] == policy["catalogue_revision"],
      do: :ok,
      else: {:error, %{code: :catalogue_revision_mismatch}}
  end

  defp select(descriptor, catalogue, policy) do
    assessed =
      catalogue["candidates"]
      |> Enum.sort_by(& &1["route"])
      |> Enum.map(&{&1, exclusions(&1, descriptor, policy)})

    eligible =
      assessed
      |> Enum.filter(fn {_, reasons} -> reasons == [] end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort_by(fn candidate ->
        {if(candidate["provider"] == descriptor["preferred_provider"], do: 0, else: 1),
         candidate["route"]}
      end)

    explanation = %{
      recommendation: List.first(eligible),
      alternatives: eligible |> Enum.drop(1) |> Enum.map(& &1["route"]),
      exclusions:
        for(
          {candidate, reasons} <- assessed,
          reasons != [],
          do: %{route: candidate["route"], reasons: reasons}
        ),
      catalogue_revision: catalogue["revision"],
      policy_revision: policy["revision"],
      unknown_availability: Map.get(policy, "unknown_availability", "exclude"),
      rules: @rules
    }

    if eligible == [],
      do: {:error, %{code: :no_route, explanation: explanation}},
      else: {:ok, explanation}
  end

  defp exclusions(candidate, descriptor, policy) do
    explicit =
      for {field, code} <- [
            {"route", :route_mismatch},
            {"provider", :provider_mismatch},
            {"model", :model_mismatch},
            {"effort", :effort_mismatch}
          ],
          Map.has_key?(descriptor, field),
          candidate[field] != descriptor[field],
          do: code

    capabilities =
      if Enum.all?(descriptor["required_capabilities"], &(&1 in candidate["capabilities"])),
        do: [],
        else: [:missing_capabilities]

    availability =
      case candidate["availability"] do
        "unavailable" ->
          [:unavailable]

        "unknown" ->
          if Map.get(policy, "unknown_availability", "exclude") == "allow",
            do: [],
            else: [:unknown_availability]

        "available" ->
          []
      end

    explicit ++ capabilities ++ availability
  end
end

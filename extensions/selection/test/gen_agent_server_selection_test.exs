defmodule GenAgentServer.SelectionTest do
  use ExUnit.Case, async: true

  alias GenAgentServer.Selection

  defp route(name, provider, overrides \\ %{}) do
    Map.merge(
      %{
        "route" => name,
        "provider" => provider,
        "model" => "configured-model",
        "effort" => "configured-effort",
        "capabilities" => ["read"],
        "availability" => "available"
      },
      overrides
    )
  end

  defp catalogue(candidates), do: %{"revision" => "catalogue-1", "candidates" => candidates}

  defp policy(overrides \\ %{}),
    do:
      Map.merge(
        %{"revision" => "policy-1", "catalogue_revision" => "catalogue-1"},
        overrides
      )

  defp descriptor(overrides \\ %{}),
    do: Map.merge(%{"required_capabilities" => ["read"]}, overrides)

  test "deterministic preference and tie breaking return configuration and revision provenance" do
    candidates = [route("z", "codex"), route("a", "claude"), route("b", "codex")]
    input = descriptor(%{"preferred_provider" => "codex"})
    assert {:ok, result} = Selection.suggest(input, catalogue(candidates), policy())
    assert result.recommendation == Enum.at(candidates, 2)
    assert result.alternatives == ["z", "a"]
    assert result.exclusions == []
    assert result.catalogue_revision == "catalogue-1"
    assert result.policy_revision == "policy-1"

    assert result.rules == [
             :explicit_constraints,
             :required_capabilities,
             :availability,
             :preferred_provider,
             :route_name
           ]

    assert Selection.explain(input, catalogue(Enum.reverse(candidates)), policy()) ==
             {:ok, result}

    assert {:ok, %{recommendation: %{"route" => "a"}}} =
             Selection.suggest(descriptor(), catalogue(candidates), policy())
  end

  test "all explicit execution settings constrain selection before preference" do
    candidates = [route("a", "claude"), route("b", "codex")]

    input =
      descriptor(%{
        "route" => "b",
        "provider" => "codex",
        "model" => "configured-model",
        "effort" => "configured-effort",
        "preferred_provider" => "claude"
      })

    assert {:ok, result} = Selection.suggest(input, catalogue(candidates), policy())
    assert result.recommendation["route"] == "b"
    assert result.exclusions == [%{route: "a", reasons: [:route_mismatch, :provider_mismatch]}]

    for {field, code} <- [
          {"route", :route_mismatch},
          {"provider", :provider_mismatch},
          {"model", :model_mismatch},
          {"effort", :effort_mismatch}
        ] do
      assert {:error, %{code: :no_route, explanation: explanation}} =
               Selection.suggest(
                 descriptor(%{field => "not-configured"}),
                 catalogue(candidates),
                 policy()
               )

      assert explanation.recommendation == nil

      assert explanation.exclusions == [
               %{route: "a", reasons: [code]},
               %{route: "b", reasons: [code]}
             ]
    end

    assert {:error, %{code: :no_route}} =
             Selection.suggest(
               descriptor(%{"route" => "a", "provider" => "codex"}),
               catalogue(candidates),
               policy()
             )
  end

  test "explicit route never bypasses capabilities or unavailable state" do
    candidates = [
      route("a", "codex", %{"capabilities" => [], "availability" => "unavailable"}),
      route("b", "claude")
    ]

    assert {:error, %{code: :no_route, explanation: result}} =
             Selection.suggest(descriptor(%{"route" => "a"}), catalogue(candidates), policy())

    assert result.exclusions == [
             %{route: "a", reasons: [:missing_capabilities, :unavailable]},
             %{route: "b", reasons: [:route_mismatch]}
           ]

    assert {:error, %{code: :no_route, explanation: %{exclusions: [%{reasons: [:unavailable]}]}}} =
             Selection.suggest(
               descriptor(),
               catalogue([route("a", "p", %{"availability" => "unavailable"})]),
               policy(%{"unknown_availability" => "allow"})
             )
  end

  test "unknown availability is explicit, excluded by default and deliberately eligible by policy" do
    candidate =
      route("a", "custom", %{"availability" => "unknown", "model" => nil, "effort" => nil})

    assert {:error, %{code: :no_route, explanation: result}} =
             Selection.suggest(descriptor(), catalogue([candidate]), policy())

    assert result.exclusions == [%{route: "a", reasons: [:unknown_availability]}]

    assert {:ok, %{recommendation: ^candidate, unknown_availability: "allow"}} =
             Selection.suggest(
               descriptor(),
               catalogue([candidate]),
               policy(%{"unknown_availability" => "allow"})
             )

    assert {:error, %{code: :no_route}} =
             Selection.suggest(
               descriptor(%{"model" => "some-model"}),
               catalogue([candidate]),
               policy(%{"unknown_availability" => "allow"})
             )
  end

  test "empty catalogue and absent preferred provider do not invent routes" do
    assert {:error, %{code: :no_route, explanation: %{exclusions: [], alternatives: []}}} =
             Selection.suggest(descriptor(), catalogue([]), policy())

    assert {:ok, %{recommendation: %{"route" => "a"}}} =
             Selection.suggest(
               descriptor(%{"preferred_provider" => "absent"}),
               catalogue([route("a", "custom")]),
               policy()
             )
  end

  test "unsupported prompts, behavioral profiles and continuation inputs are rejected" do
    for field <- ~w(prompt policy_text role profile session_id continuation) do
      assert {:error, %{code: :unsupported_fields, input: :descriptor}} =
               Selection.suggest(
                 descriptor(%{field => "arbitrary text"}),
                 catalogue([]),
                 policy()
               )
    end

    assert {:error, %{code: :unsupported_fields, input: :candidate}} =
             Selection.suggest(
               descriptor(),
               catalogue([route("a", "custom", %{"permission" => "write"})]),
               policy()
             )

    assert {:error, %{code: :unsupported_fields, input: :policy}} =
             Selection.suggest(descriptor(), catalogue([]), policy(%{"prompt" => "choose"}))

    assert {:error, %{code: :unsupported_fields, input: :catalogue}} =
             Selection.suggest(descriptor(), Map.put(catalogue([]), "models", []), policy())
  end

  test "malformed inputs and catalogue conflicts return typed errors" do
    for bad <- [
          nil,
          [],
          "prompt",
          %{},
          %{"required_capabilities" => "read"},
          descriptor(%{"model" => nil}),
          descriptor(%{"route" => 12}),
          descriptor(%{"required_capabilities" => [1]}),
          descriptor(%{"required_capabilities" => ["read" | :invalid]})
        ] do
      assert {:error, %{code: :invalid_input, input: :descriptor}} =
               Selection.suggest(bad, catalogue([]), policy())
    end

    for bad <- [
          nil,
          %{},
          %{"revision" => "r", "candidates" => nil},
          catalogue([route("a", "p") | :invalid])
        ] do
      assert {:error, %{code: :invalid_input, input: :catalogue}} =
               Selection.suggest(descriptor(), bad, policy())
    end

    for bad <- [
          nil,
          %{},
          route("a", "p", %{"availability" => "healthy"}),
          route("a", "p", %{"capabilities" => nil}),
          route("a", "p", %{"capabilities" => ["read" | :invalid]}),
          route("", "p"),
          Map.delete(route("a", "p"), "effort")
        ] do
      assert {:error, %{code: :invalid_input, input: :candidate}} =
               Selection.suggest(descriptor(), catalogue([bad]), policy())
    end

    for bad <- [nil, %{}, policy(%{"unknown_availability" => true})] do
      assert {:error, %{code: :invalid_input, input: :policy}} =
               Selection.suggest(descriptor(), catalogue([]), bad)
    end

    assert {:error, %{code: :duplicate_route}} =
             Selection.suggest(
               descriptor(),
               catalogue([route("a", "p"), route("a", "q")]),
               policy()
             )

    assert {:error, %{code: :catalogue_revision_mismatch}} =
             Selection.suggest(
               descriptor(),
               catalogue([]),
               policy(%{"catalogue_revision" => "stale"})
             )
  end

  test "repeated pure calls leave caller state and mailbox untouched and accept unknown identifiers" do
    provider = "operator-custom-provider-#{System.unique_integer([:positive])}"
    assert_raise ArgumentError, fn -> String.to_existing_atom(provider) end
    input = descriptor(%{"provider" => provider})
    candidates = catalogue([route("custom", provider)])
    dictionary = Process.get()
    assert {:ok, result} = Selection.suggest(input, candidates, policy())
    assert Selection.suggest(input, candidates, policy()) == {:ok, result}
    assert Process.get() == dictionary
    refute_receive _
    assert result.recommendation["provider"] == provider
    assert_raise ArgumentError, fn -> String.to_existing_atom(provider) end
  end
end

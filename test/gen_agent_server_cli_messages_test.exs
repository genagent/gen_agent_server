defmodule GenAgentServer.CLIMessagesTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  alias CodexWrapper.JsonLineEvent
  alias GenAgent.Event
  alias GenAgent.Backends.Codex.EventTranslator

  defmodule ScriptedBackend do
    @behaviour GenAgent.Backend

    def start_session(_opts), do: {:ok, :ready}

    def prompt(session, "multi") do
      raw = [
        %JsonLineEvent{
          event_type: "item.completed",
          data: %{"item" => %{"type" => "agent_message", "text" => "Checking.\n\nMore work."}}
        },
        %JsonLineEvent{
          event_type: "item.completed",
          data: %{"item" => %{"type" => "agent_message", "text" => "Final answer.\n\nDetails."}}
        },
        %JsonLineEvent{event_type: "turn.completed", data: %{}}
      ]

      {:ok, EventTranslator.translate(raw), session}
    end

    def prompt(session, "codex-single") do
      raw = [
        %JsonLineEvent{
          event_type: "item.completed",
          data: %{"item" => %{"type" => "agent_message", "text" => "One Codex answer."}}
        },
        %JsonLineEvent{event_type: "turn.completed", data: %{}}
      ]

      {:ok, EventTranslator.translate(raw), session}
    end

    def prompt(session, "claude-single"),
      do: {:ok, [Event.new(:result, %{text: "One Claude answer."})], session}

    def update_session(session, _event), do: session
    def terminate_session(_session), do: :ok
  end

  setup do
    name = "cli-messages-#{System.unique_integer([:positive])}"
    agents = [{"scripted", GenAgentEnsemble.Agents.Simple, [backend: ScriptedBackend]}]
    assert {:ok, _pid} = GenAgentServer.start_instance(name, agents)
    on_exit(fn -> GenAgentServer.stop_instance(name) end)
    %{name: name}
  end

  test "local and remote CLI show the final Codex message while the API keeps both", %{name: name} do
    prefix = ["--instance", name]
    assert {:ok, id} = GenAgentServer.CLI.run(prefix ++ ["invoke", "scripted", "multi"])
    assert {:ok, :completed, response} = await_result(name, id)

    assert response.text == "Checking.\n\nMore work.\n\nFinal answer.\n\nDetails."
    assert response.final_message == "Final answer.\n\nDetails."
    assert Enum.count(response.events, &(&1.kind == :text)) == 2
    assert {:ok, :completed, ^response} = GenAgentServer.result(name, id)

    assert {:ok, "Final answer.\n\nDetails."} =
             GenAgentServer.CLI.run(prefix ++ ["result", id])

    assert capture_io(fn -> GenAgentServer.CLI.main(prefix ++ ["ask", "scripted", "multi"]) end) ==
             "Final answer.\n\nDetails.\n"

    remote_output =
      capture_io(fn -> GenAgentServer.CLI.remote_main(prefix ++ ["result", id]) end)

    assert {:ok, "Final answer.\n\nDetails."} =
             GenAgentServer.Remote.decode_response(remote_output)
  end

  test "single-message Codex and Claude turns keep their original CLI text", %{name: name} do
    for {prompt, expected} <- [
          {"codex-single", "One Codex answer."},
          {"claude-single", "One Claude answer."}
        ] do
      args = ["--instance", name, "ask", "scripted", prompt]
      assert {:ok, ^expected} = GenAgentServer.CLI.run(args)

      remote_output = capture_io(fn -> GenAgentServer.CLI.remote_main(args) end)

      assert {:ok, ^expected} =
               GenAgentServer.Remote.decode_response(remote_output)
    end
  end

  test "CLI presents an Ensemble synthesized response with no final_message" do
    name = "cli-supervisor-#{System.unique_integer([:positive])}"
    simple = GenAgentEnsemble.Agents.Simple
    echo = GenAgentEnsemble.Backends.Echo

    opts = [
      coordinator: {"coordinator", simple, [backend: echo]},
      worker_template: {"worker", simple, [backend: echo]},
      decomposer: fn _text -> ["first", "second"] end
    ]

    assert {:ok, _pid} =
             GenAgentServer.start_pattern_instance(
               name,
               "review",
               GenAgentEnsemble.Strategies.Supervisor,
               opts
             )

    on_exit(fn -> GenAgentServer.stop_instance(name) end)

    prefix = ["--instance", name]
    assert {:ok, id} = GenAgentServer.CLI.run(prefix ++ ["invoke", "review", "two parts"])
    assert {:ok, :completed, response} = await_result(name, id)
    assert response.text == "echo: first\n\necho: second"
    assert Map.get(response, :final_message) == nil
    assert {:ok, response.text} == GenAgentServer.CLI.run(prefix ++ ["result", id])

    remote_output = capture_io(fn -> GenAgentServer.CLI.remote_main(prefix ++ ["result", id]) end)
    assert {:ok, response.text} == GenAgentServer.Remote.decode_response(remote_output)
  end

  defp await_result(name, id, attempts \\ 100)

  defp await_result(_name, _id, 0), do: flunk("invocation did not complete")

  defp await_result(name, id, attempts) do
    case GenAgentServer.result(name, id) do
      {:ok, :pending} ->
        Process.sleep(10)
        await_result(name, id, attempts - 1)

      result ->
        result
    end
  end
end

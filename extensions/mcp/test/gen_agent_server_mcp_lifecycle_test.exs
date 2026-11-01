defmodule GenAgentServer.MCPLifecycleTest do
  use ExUnit.Case, async: false

  alias GenAgentServer.MCP

  # Stands in for the Claude CLI backend. It reports the options the real
  # backend would receive and echoes them in each response.
  defmodule Recorder do
    @behaviour GenAgent.Backend

    alias GenAgent.Event

    defstruct [:opts]

    @impl true
    def start_session(opts) do
      send(Keyword.fetch!(opts, :test_pid), {:backend_started, Keyword.delete(opts, :test_pid)})
      {:ok, %__MODULE__{opts: opts}}
    end

    @impl true
    def prompt(%__MODULE__{opts: opts} = session, prompt) do
      text = "model=#{opts[:model] || "default"} effort=#{opts[:effort] || "none"}: #{prompt}"
      {:ok, [Event.new(:result, %{text: text})], session}
    end

    @impl true
    def update_session(session, _data), do: session

    @impl true
    def terminate_session(_session), do: :ok
  end

  setup do
    suffix = System.unique_integer([:positive])
    dir = Path.join(System.tmp_dir!(), "gen-agent-lifecycle-#{suffix}")
    File.mkdir_p!(dir)

    previous = Application.get_env(:gen_agent_server, :provider_overrides)

    Application.put_env(:gen_agent_server, :provider_overrides, %{
      "claude" => [backend: Recorder, test_pid: self()]
    })

    on_exit(fn ->
      if previous,
        do: Application.put_env(:gen_agent_server, :provider_overrides, previous),
        else: Application.delete_env(:gen_agent_server, :provider_overrides)

      for name <- GenAgentServer.instances(), String.starts_with?(name, "life-#{suffix}") do
        GenAgentServer.stop_instance(name)
      end

      File.rm_rf!(dir)
    end)

    {:ok, client} = Snodo.Client.direct(MCP.Server.runtime())
    %{client: client, suffix: suffix, dir: dir, name: "life-#{suffix}"}
  end

  defp config(dir) do
    %{
      "cwd" => dir,
      "max_in_flight" => 2,
      "max_results" => 10,
      "routes" => [
        %{"name" => "fast", "provider" => "claude", "model" => "haiku-test", "effort" => "low"},
        %{
          "name" => "deep",
          "provider" => "claude",
          "model" => "opus-test",
          "effort" => "max",
          "claude_permission_mode" => "accept_edits"
        },
        %{"name" => "plain", "provider" => "echo"}
      ]
    }
  end

  describe "MCP lifecycle" do
    test "Codex response text flows through actual MCP lifecycle and resumed results", %{
      client: client,
      name: name,
      dir: dir
    } do
      observer = self()

      exec_fn = fn prompt, session ->
        send(observer, {:codex_exec, prompt, session.thread_id, session.response_text})

        {thread_id, commentary, final, usage} =
          case prompt do
            "default" -> {"thread-default", "default commentary", "default final", {5, 1}}
            "first" -> {"thread-final", "first commentary", ~s({"answer":1}), {10, 2}}
            "second" -> {"thread-final", "second commentary", ~s({"answer":2}), {20, 4}}
          end

        ndjson =
          [
            %{"type" => "thread.started", "thread_id" => thread_id},
            %{
              "type" => "item.completed",
              "item" => %{"type" => "agent_message", "text" => commentary}
            },
            %{
              "type" => "item.completed",
              "item" => %{"type" => "agent_message", "text" => final}
            },
            %{
              "type" => "turn.completed",
              "usage" => %{"input_tokens" => elem(usage, 0), "output_tokens" => elem(usage, 1)}
            }
          ]
          |> Enum.map_join("\n", &Jason.encode!/1)

        {:ok, CodexWrapper.JsonLineEvent.parse_lines(ndjson)}
      end

      overrides = Application.get_env(:gen_agent_server, :provider_overrides, %{})

      Application.put_env(
        :gen_agent_server,
        :provider_overrides,
        Map.put(overrides, "codex", exec_fn: exec_fn)
      )

      config = %{
        "cwd" => dir,
        "routes" => [
          %{"name" => "joined", "provider" => "codex"},
          %{
            "name" => "final",
            "provider" => "codex",
            "codex_response_text" => "final_message"
          }
        ]
      }

      created = ok!(client, "create_instance", %{"instance" => name, "config" => config})

      assert %{
               "routes" => [
                 %{"name" => "joined", "codex_response_text" => "all_messages"},
                 %{"name" => "final", "codex_response_text" => "final_message"}
               ]
             } = created

      assert ok!(client, "describe_instance", %{"instance" => name}) == created

      assert %{"id" => default_id} =
               ok!(client, "invoke", %{
                 "instance" => name,
                 "agent" => "joined",
                 "prompt" => "default"
               })

      assert eventually(fn ->
               match?(
                 %{"status" => "completed"},
                 ok!(client, "result", %{"instance" => name, "id" => default_id})
               )
             end)

      assert %{"text" => "default commentary\n\ndefault final"} =
               ok!(client, "result", %{"instance" => name, "id" => default_id})

      assert_receive {:codex_exec, "default", nil, :all_messages}

      assert %{"id" => first_id} =
               ok!(client, "invoke", %{
                 "instance" => name,
                 "agent" => "final",
                 "prompt" => "first"
               })

      assert eventually(fn ->
               match?(
                 %{"status" => "completed"},
                 ok!(client, "result", %{"instance" => name, "id" => first_id})
               )
             end)

      first = ok!(client, "result", %{"instance" => name, "id" => first_id})
      assert first["text"] == ~s({"answer":1})
      assert Jason.decode!(first["text"]) == %{"answer" => 1}
      assert ok!(client, "result", %{"instance" => name, "id" => first_id}) == first
      assert_receive {:codex_exec, "first", nil, :final_message}
      refute_received {:codex_exec, "first", _, _}

      assert {:ok, :completed, response} = GenAgentServer.result(name, first_id)

      assert for(%GenAgent.Event{kind: :text, data: %{text: text}} <- response.events, do: text) ==
               ["first commentary", ~s({"answer":1})]

      assert %{"id" => second_id} =
               ok!(client, "invoke", %{
                 "instance" => name,
                 "agent" => "final",
                 "prompt" => "second"
               })

      assert eventually(fn ->
               match?(
                 %{"status" => "completed", "text" => ~s({"answer":2})},
                 ok!(client, "result", %{"instance" => name, "id" => second_id})
               )
             end)

      assert_receive {:codex_exec, "second", "thread-final", :final_message}
      second = ok!(client, "result", %{"instance" => name, "id" => second_id})
      assert second["session_id"] == first["session_id"]
      assert ok!(client, "result", %{"instance" => name, "id" => second_id}) == second
      refute_received {:codex_exec, "second", _, _}
    end

    test "a client creates, inspects, invokes, and stops a model-specific route", %{
      client: client,
      name: name,
      dir: dir
    } do
      created = ok!(client, "create_instance", %{"instance" => name, "config" => config(dir)})
      assert created["configured"] == true
      assert hd(created["routes"])["claude_permission_mode"] == "inherit"
      assert Enum.map(created["routes"], & &1["name"]) == ["fast", "deep", "plain"]

      assert ok!(client, "describe_instance", %{"instance" => name}) == created
      assert name in ok!(client, "instances", %{})["instances"]

      assert %{"text" => "model=opus-test effort=max: plan"} =
               ok!(client, "ask", %{"instance" => name, "agent" => "deep", "prompt" => "plan"})

      assert %{"id" => id} =
               ok!(client, "invoke", %{"instance" => name, "agent" => "fast", "prompt" => "go"})

      assert eventually(fn ->
               match?(
                 %{"status" => "completed"},
                 ok!(client, "result", %{"instance" => name, "id" => id})
               )
             end)

      first = ok!(client, "result", %{"instance" => name, "id" => id})
      assert first["text"] == "model=haiku-test effort=low: go"
      assert ok!(client, "result", %{"instance" => name, "id" => id}) == first

      assert %{"stopped" => true} = ok!(client, "stop_instance", %{"instance" => name})
      assert error!(client, "describe_instance", %{"instance" => name}) =~ "instance_not_found"
      assert error!(client, "stop_instance", %{"instance" => name}) =~ "not_found"
    end

    test "invalid creation is a tool error and starts nothing", %{
      client: client,
      name: name,
      dir: dir
    } do
      before = GenAgentServer.instances()

      bad = %{
        "cwd" => dir,
        "routes" => [%{"name" => "r", "provider" => "claude", "effort" => "ultra"}]
      }

      assert error!(client, "create_instance", %{"instance" => name, "config" => bad}) =~
               "invalid_config"

      unknown = %{"routes" => [%{"name" => "r", "provider" => "echo"}], "module" => "Elixir.File"}

      assert error!(client, "create_instance", %{"instance" => name, "config" => unknown}) =~
               "invalid_config"

      assert GenAgentServer.instances() == before
      refute_received {:backend_started, _}

      assert error!(client, "stop_instance", %{"instance" => GenAgentServer.session_name()}) =~
               "default_instance"

      assert GenAgentServer.session_name() in GenAgentServer.instances()
    end
  end

  # -- helpers -----------------------------------------------------------------

  defp ok!(client, name, args) do
    {:ok, result} = Snodo.Client.call_tool(client, name, args)
    result = plain(result)
    refute field(result, "isError", :is_error), "#{name} failed: #{inspect(result)}"
    field(result, "structuredContent", :structured_content)
  end

  defp error!(client, name, args) do
    {:ok, result} = Snodo.Client.call_tool(client, name, args)
    result = plain(result)
    assert field(result, "isError", :is_error) == true, "#{name} succeeded: #{inspect(result)}"

    result
    |> field("content", :content)
    |> Enum.map_join(" ", &field(&1, "text", :text))
  end

  defp field(map, wire, atom), do: Map.get(map, wire, Map.get(map, atom))

  defp plain(%_{} = struct), do: struct |> Map.from_struct() |> plain()
  defp plain(map) when is_map(map), do: Map.new(map, fn {k, v} -> {k, plain(v)} end)
  defp plain(list) when is_list(list), do: Enum.map(list, &plain/1)
  defp plain(other), do: other

  defp eventually(fun, attempts \\ 200) do
    cond do
      fun.() -> true
      attempts == 0 -> false
      true -> Process.sleep(10) && eventually(fun, attempts - 1)
    end
  end
end

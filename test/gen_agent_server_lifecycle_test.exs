defmodule GenAgentServer.LifecycleTest do
  use ExUnit.Case, async: false

  alias GenAgentServer.{MCP, Ops}

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

  describe "Ops lifecycle" do
    test "creation and stopping require an explicit instance name", %{dir: dir} do
      assert {:error, %{code: "invalid_args", message: "missing required argument: instance"}} =
               Ops.call("create_instance", %{"config" => config(dir)})

      assert {:error, %{code: "invalid_args", message: "missing required argument: instance"}} =
               Ops.call("stop_instance", %{})
    end

    test "create, describe, invoke, read results, and stop", %{name: name, dir: dir} do
      assert {:ok, created} =
               Ops.call("create_instance", %{"instance" => name, "config" => config(dir)})

      assert {:ok, ^created} = Ops.call("describe_instance", %{"instance" => name})
      assert {:ok, _} = Jason.encode(created)

      assert %{
               "instance" => ^name,
               "configured" => true,
               "strategy" => "GenAgentEnsemble.Strategies.Switchboard",
               "limits" => %{"max_in_flight" => 2, "max_results" => 10},
               "routes" => [fast, deep, plain]
             } = created

      assert fast == %{
               "name" => "fast",
               "provider" => "claude",
               "model" => "haiku-test",
               "effort" => "low",
               "cwd" => dir,
               "claude_permission_mode" => "read_only"
             }

      assert %{"claude_permission_mode" => "accept_edits", "effort" => "max"} = deep
      assert %{"provider" => "echo", "model" => nil, "effort" => nil, "cwd" => nil} = plain

      assert {:ok, %{agents: ["deep", "fast", "plain"]}} =
               Ops.call("agents", %{"instance" => name})

      assert {:ok, %{status: "completed", text: "model=haiku-test effort=low: hi"}} =
               Ops.call("ask", %{"instance" => name, "agent" => "fast", "prompt" => "hi"})

      assert {:ok, %{status: "completed", text: "model=opus-test effort=max: hi"}} =
               Ops.call("ask", %{"instance" => name, "agent" => "deep", "prompt" => "hi"})

      assert {:ok, %{status: "completed", text: "echo: hi"}} =
               Ops.call("ask", %{"instance" => name, "agent" => "plain", "prompt" => "hi"})

      started = for _ <- 1..2, do: receive_started()
      by_model = Map.new(started, &{&1[:model], &1})

      assert %{
               permission_mode: :dont_ask,
               tools: ["Read", "Grep", "Glob"],
               effort: :low,
               cwd: ^dir
             } = Map.new(by_model["haiku-test"])

      assert %{permission_mode: :accept_edits, effort: :max} = Map.new(by_model["opus-test"])

      assert {:ok, %{id: id}} =
               Ops.call("invoke", %{"instance" => name, "agent" => "fast", "prompt" => "later"})

      assert eventually(fn ->
               match?(
                 {:ok, %{status: "completed"}},
                 Ops.call("result", %{"instance" => name, "id" => id})
               )
             end)

      {:ok, first} = Ops.call("result", %{"instance" => name, "id" => id})
      assert first.text == "model=haiku-test effort=low: later"
      assert {:ok, ^first} = Ops.call("result", %{"instance" => name, "id" => id})

      assert {:ok, %{instance: ^name, stopped: true}} =
               Ops.call("stop_instance", %{"instance" => name})

      assert {:error, %{code: "instance_not_found"}} =
               Ops.call("describe_instance", %{"instance" => name})

      assert {:error, %{code: "instance_not_found"}} =
               Ops.call("result", %{"instance" => name, "id" => id})
    end

    test "two instances keep independent models and results", %{name: name, dir: dir} do
      one = name <> "-a"
      two = name <> "-b"

      route = fn model ->
        %{"routes" => [%{"name" => "w", "provider" => "claude", "model" => model}], "cwd" => dir}
      end

      assert {:ok, _} =
               Ops.call("create_instance", %{"instance" => one, "config" => route.("m-one")})

      assert {:ok, _} =
               Ops.call("create_instance", %{"instance" => two, "config" => route.("m-two")})

      assert {:ok, %{text: "model=m-one effort=none: x"}} =
               Ops.call("ask", %{"instance" => one, "agent" => "w", "prompt" => "x"})

      assert {:ok, %{text: "model=m-two effort=none: x"}} =
               Ops.call("ask", %{"instance" => two, "agent" => "w", "prompt" => "x"})

      assert {:ok, %{"routes" => [%{"model" => "m-one"}]}} =
               Ops.call("describe_instance", %{"instance" => one})

      assert :ok = GenAgentServer.stop_instance(one)

      assert {:ok, %{"routes" => [%{"model" => "m-two"}]}} =
               Ops.call("describe_instance", %{"instance" => two})
    end

    test "creation validates everything before starting any backend", %{name: name, dir: dir} do
      route = %{"name" => "r", "provider" => "claude"}
      missing = Path.join(dir, "missing")
      before = GenAgentServer.instances()

      invalid = [
        %{"routes" => [route], "cwd" => dir, "backend_opts" => %{}},
        %{"routes" => [route], "cwd" => dir, "strategy" => "pool"},
        %{"routes" => [route], "cwd" => dir, "pattern" => "debate"},
        %{"routes" => [Map.put(route, "module", "Elixir.File")], "cwd" => dir},
        %{"routes" => [Map.put(route, "provider", "gemini")], "cwd" => dir},
        %{"routes" => [Map.put(route, "model", "--dangerous")], "cwd" => dir},
        %{"routes" => [Map.put(route, "model", "")], "cwd" => dir},
        %{"routes" => [Map.put(route, "model", 7)], "cwd" => dir},
        %{"routes" => [Map.put(route, "model", String.duplicate("m", 129))], "cwd" => dir},
        %{"routes" => [Map.put(route, "effort", "ultra")], "cwd" => dir},
        %{"routes" => [Map.put(route, "effort", ["high"])], "cwd" => dir},
        %{"routes" => [%{"name" => "c", "provider" => "codex", "effort" => "max"}], "cwd" => dir},
        %{"routes" => [%{"name" => "e", "provider" => "echo", "effort" => "low"}]},
        %{"routes" => [%{"name" => "e", "provider" => "echo", "model" => "m"}]},
        %{"routes" => [%{"name" => "e", "provider" => "echo", "codex_sandbox" => "read_only"}]},
        %{"routes" => [route]},
        %{"routes" => [route], "cwd" => "relative/dir"},
        %{"routes" => [route], "cwd" => missing},
        %{"routes" => [Map.put(route, "codex_sandbox", "workspace_write")], "cwd" => dir},
        %{"routes" => [Map.put(route, "claude_permission_mode", "bypass")], "cwd" => dir},
        %{"routes" => [route, route], "cwd" => dir},
        %{"routes" => [Map.put(route, "name", "a/b")], "cwd" => dir},
        %{"routes" => [], "cwd" => dir},
        %{"routes" => for(n <- 1..17, do: %{"name" => "r#{n}", "provider" => "echo"})},
        %{"routes" => "claude"},
        %{"cwd" => dir},
        %{"routes" => [route], "cwd" => dir, "max_in_flight" => 0},
        %{"routes" => [route], "cwd" => dir, "max_in_flight" => 65},
        %{"routes" => [route], "cwd" => dir, "max_results" => 1001},
        %{"routes" => [route], "cwd" => dir, "max_results" => "all"}
      ]

      for config <- invalid do
        assert {:error, %{code: "invalid_config", message: message}} =
                 Ops.call("create_instance", %{"instance" => name, "config" => config}),
               "accepted #{inspect(config)}"

        assert is_binary(message) and message != ""
      end

      for bad <- ["bad name", "../x", "-x", String.duplicate("a", 65)] do
        assert {:error, %{code: "invalid_instance_name"}} =
                 Ops.call("create_instance", %{"instance" => bad, "config" => %{"routes" => []}})
      end

      assert GenAgentServer.instances() == before
      refute_received {:backend_started, _}
    end

    test "duplicate names are rejected, including concurrent creation", %{name: name, dir: dir} do
      args = %{"instance" => name, "config" => config(dir)}

      results =
        1..8
        |> Enum.map(fn _ -> Task.async(fn -> Ops.call("create_instance", args) end) end)
        |> Task.await_many(10_000)

      assert Enum.count(results, &match?({:ok, _}, &1)) == 1
      assert Enum.count(results, &match?({:error, %{code: "instance_exists"}}, &1)) == 7
      assert Enum.count(GenAgentServer.instances(), &(&1 == name)) == 1

      assert {:error, %{code: "instance_exists"}} = Ops.call("create_instance", args)

      assert {:error, %{code: "invalid_instance_name"}} =
               Ops.call("create_instance", %{
                 "instance" => GenAgentServer.session_name(),
                 "config" => %{"routes" => [%{"name" => "x", "provider" => "echo"}]}
               })
    end

    test "the default instance cannot be stopped and legacy instances describe as unconfigured" do
      default = GenAgentServer.session_name()

      assert {:error, %{code: "default_instance"}} =
               Ops.call("stop_instance", %{"instance" => default})

      assert default in GenAgentServer.instances()

      assert {:ok,
              %{"configured" => false, "routes" => routes, "limits" => %{"max_in_flight" => _}}} =
               Ops.call("describe_instance", %{})

      assert %{"name" => "echo"} in routes

      assert {:error, %{code: "not_found"}} = Ops.call("stop_instance", %{"instance" => "nope"})

      assert {:error, %{code: "instance_not_found"}} =
               Ops.call("describe_instance", %{"instance" => "nope"})
    end

    test "creation arguments are checked against the operation schema" do
      assert {:error, %{code: "invalid_args"}} = Ops.call("create_instance", %{"instance" => "x"})

      assert {:error, %{code: "invalid_args"}} =
               Ops.call("create_instance", %{"instance" => "x", "config" => "routes"})

      assert {:error, %{code: "invalid_args"}} =
               Ops.call("create_instance", %{"instance" => "x", "config" => %{}, "agents" => []})

      assert Enum.find(Ops.list(), &(&1.name == "create_instance")).mutates
      refute Enum.find(Ops.list(), &(&1.name == "describe_instance")).mutates
    end
  end

  describe "Codex effort" do
    # A fake `codex` that logs its arguments and emits one thread and one
    # message, so the real adapter builds both a fresh and a resumed command.
    setup %{dir: dir} do
      log = Path.join(dir, "args.log")
      binary = Path.join(dir, "codex")

      File.write!(binary, """
      #!/bin/sh
      printf '%s\\n' "$*" >> #{log}
      printf '%s\\n' '{"type":"thread.started","thread_id":"thread-1"}'
      printf '%s\\n' '{"type":"item.completed","item":{"type":"agent_message","text":"ok"}}'
      printf '%s\\n' '{"type":"turn.completed","usage":{"input_tokens":1,"output_tokens":1}}'
      """)

      File.chmod!(binary, 0o755)

      overrides = Application.get_env(:gen_agent_server, :provider_overrides)

      Application.put_env(
        :gen_agent_server,
        :provider_overrides,
        Map.put(overrides, "codex", binary: binary)
      )

      %{log: log}
    end

    test "model and effort reach fresh and resumed turns", %{name: name, dir: dir, log: log} do
      config = %{
        "cwd" => dir,
        "routes" => [
          %{"name" => "coder", "provider" => "codex", "model" => "gpt-test", "effort" => "high"}
        ]
      }

      assert {:ok, %{"routes" => [%{"effort" => "high", "codex_sandbox" => "read_only"}]}} =
               Ops.call("create_instance", %{"instance" => name, "config" => config})

      for prompt <- ["first", "second"] do
        assert {:ok, %{status: "completed", text: "ok"}} =
                 Ops.call("ask", %{"instance" => name, "agent" => "coder", "prompt" => prompt})
      end

      assert [fresh, resumed] = log |> File.read!() |> String.split("\n", trim: true)
      assert fresh =~ ~r/\bexec\b/
      refute fresh =~ "exec resume"
      assert resumed =~ "exec resume"

      for line <- [fresh, resumed] do
        assert line =~ ~s(model_reasoning_effort="high")
        assert line =~ "gpt-test"
        assert line =~ "--ignore-user-config"
      end
    end
  end

  describe "MCP lifecycle" do
    test "a client creates, inspects, invokes, and stops a model-specific route", %{
      client: client,
      name: name,
      dir: dir
    } do
      created = ok!(client, "create_instance", %{"instance" => name, "config" => config(dir)})
      assert created["configured"] == true
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

  defp receive_started do
    receive do
      {:backend_started, opts} -> opts
    after
      2_000 -> flunk("backend did not start")
    end
  end

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

defmodule GenAgentServer.RunTest do
  use ExUnit.Case, async: false

  alias GenAgentServer.{PatternSpec, Providers, Run}

  @echo %{"provider" => "echo"}

  describe "Providers" do
    test "maps known providers and rejects unknown ones" do
      assert {:ok, [backend: GenAgentEnsemble.Backends.Echo]} = Providers.backend_opts("echo")
      assert {:error, :cwd_required} = Providers.backend_opts("codex", [])

      assert {:ok, opts} = Providers.backend_opts("codex", cwd: File.cwd!(), model: "m")

      assert opts[:sandbox] == :read_only and opts[:approval_policy] == :never and
               opts[:model] == "m"

      assert opts[:working_dir] == File.cwd!()
      refute Keyword.has_key?(opts, :cwd)

      assert opts[:ignore_user_config] == true

      assert {:ok, inherited} =
               Providers.backend_opts("codex",
                 cwd: File.cwd!(),
                 codex_user_config: :inherit
               )

      refute Keyword.has_key?(inherited, :ignore_user_config)

      assert {:ok, opts} = Providers.backend_opts("claude", cwd: File.cwd!())
      assert opts[:permission_mode] == :plan
      assert opts[:working_dir] == File.cwd!()
      refute Keyword.has_key?(opts, :cwd)

      assert {:error, {:invalid_option, :codex_sandbox, :danger_full_access}} =
               Providers.backend_opts("codex",
                 cwd: File.cwd!(),
                 codex_sandbox: :danger_full_access
               )

      assert {:error, {:invalid_option, :codex_user_config, :unknown}} =
               Providers.backend_opts("codex",
                 cwd: File.cwd!(),
                 codex_user_config: :unknown
               )

      assert {:error, {:unknown_provider, "gemini"}} = Providers.backend_opts("gemini")
    end
  end

  describe "PatternSpec.parse/2" do
    test "builds every pattern from data" do
      specs = [
        %{"pattern" => "solo", "agent" => @echo},
        %{"pattern" => "switchboard", "agents" => [Map.put(@echo, "name", "a")]},
        %{"pattern" => "pipeline", "stages" => [@echo, @echo]},
        %{"pattern" => "pool", "worker_count" => 2, "worker" => @echo},
        %{"pattern" => "supervisor", "coordinator" => @echo, "worker" => @echo},
        %{"pattern" => "debate", "agents" => [@echo, @echo]},
        %{"pattern" => "consensus", "agents" => [@echo, @echo], "verdicts" => ["yes", "no"]}
      ]

      for spec <- specs do
        assert {:ok, %{strategy: strategy, routes: [_ | _]}} = PatternSpec.parse(spec)
        assert is_atom(strategy)
      end
    end

    test "rejects invalid specs with a reason" do
      assert {:error, :pattern_required} = PatternSpec.parse(%{})
      assert {:error, {:unknown_pattern, "mesh"}} = PatternSpec.parse(%{"pattern" => "mesh"})

      assert {:error, {:needs_agents, "debater", 2}} =
               PatternSpec.parse(%{"pattern" => "debate", "agents" => [@echo]})

      assert {:error, {:expected_agents, 2, 3}} =
               PatternSpec.parse(%{"pattern" => "debate", "agents" => [@echo, @echo, @echo]})

      assert {:error, :duplicate_agent_names} =
               PatternSpec.parse(%{
                 "pattern" => "pipeline",
                 "stages" => [Map.put(@echo, "name", "x"), Map.put(@echo, "name", "x")]
               })

      assert {:error, {:required, "worker_count"}} =
               PatternSpec.parse(%{"pattern" => "pool", "worker" => @echo})

      assert {:error, {:invalid, "verdicts", ["ok!"]}} =
               PatternSpec.parse(%{
                 "pattern" => "consensus",
                 "agents" => [@echo, @echo],
                 "verdicts" => ["ok!"]
               })

      assert {:error, {:invalid, "threshold", 5}} =
               PatternSpec.parse(%{
                 "pattern" => "consensus",
                 "agents" => [@echo, @echo],
                 "verdicts" => ["yes"],
                 "threshold" => 5
               })

      assert {:error, {:invalid_role, "member-1"}} =
               PatternSpec.parse(%{
                 "pattern" => "consensus",
                 "agents" => [Map.put(@echo, "role", 7), @echo],
                 "verdicts" => ["yes"]
               })
    end

    test "edit modes are opt-in and limited to the profile choices" do
      codex = %{"pattern" => "solo", "agent" => %{"provider" => "codex"}}

      assert {:ok, %{strategy_opts: [agent: {_, _, opts}]}} =
               PatternSpec.parse(codex, cwd: File.cwd!())

      assert opts[:sandbox] == :read_only
      assert opts[:ignore_user_config] == true

      assert {:ok, %{strategy_opts: [agent: {_, _, opts}]}} =
               PatternSpec.parse(Map.put(codex, "codex_sandbox", "workspace_write"),
                 cwd: File.cwd!()
               )

      assert opts[:sandbox] == :workspace_write

      assert {:ok, %{strategy_opts: [agent: {_, _, inherited}]}} =
               PatternSpec.parse(Map.put(codex, "codex_user_config", "inherit"),
                 cwd: File.cwd!()
               )

      refute Keyword.has_key?(inherited, :ignore_user_config)

      assert {:error, {:invalid, "codex_user_config", "unknown"}} =
               PatternSpec.parse(Map.put(codex, "codex_user_config", "unknown"),
                 cwd: File.cwd!()
               )

      assert {:error, {:invalid, "codex_sandbox", "danger_full_access"}} =
               PatternSpec.parse(Map.put(codex, "codex_sandbox", "danger_full_access"),
                 cwd: File.cwd!()
               )
    end

    test "numbered decomposer reads list items and caps the count" do
      {:ok, split} = PatternSpec.decomposer("numbered", 2)
      assert split.("Plan:\n1. alpha\n2) beta\n- gamma") == ["alpha", "beta"]

      {:ok, split} = PatternSpec.decomposer("lines", 5)
      assert split.(" a \n\n b") == ["a", "b"]
    end

    test "verdict parser uses the last VERDICT line and only allowed words" do
      verdicts = %{"approve" => :approve, "reject" => :reject}

      assert {:ok, :reject, "Looks risky."} =
               PatternSpec.parse_verdict("Looks risky.\nVERDICT: **Reject**", verdicts)

      assert :error = PatternSpec.parse_verdict("VERDICT: maybe", verdicts)
      assert :error = PatternSpec.parse_verdict("no verdict here", verdicts)
    end
  end

  describe "Run.run/3 with the Echo backend" do
    test "pipeline passes each stage's output to the next" do
      spec = %{"pattern" => "pipeline", "stages" => [@echo, Map.put(@echo, "role", "Revise:")]}
      assert {:ok, %{results: [item]} = report} = Run.run(spec, ["draft"])
      assert item.status == :completed
      assert item.text == "echo: Revise:\n\necho: draft"
      assert_stopped(report.instance)
    end

    test "pool runs several prompts and returns them in submission order" do
      spec = %{"pattern" => "pool", "worker_count" => 2, "worker" => @echo}
      assert {:ok, %{results: items}} = Run.run(spec, ["a", "b", "c"])
      assert Enum.map(items, & &1.text) == ["echo: a", "echo: b", "echo: c"]
    end

    test "switchboard routes to the named agent and rejects unknown routes" do
      spec = %{
        "pattern" => "switchboard",
        "agents" => [
          Map.put(@echo, "name", "a"),
          Map.merge(@echo, %{"name" => "b", "role" => "B"})
        ]
      }

      assert {:ok, %{results: [%{route: "b", text: "echo: B\n\nhi"}]}} =
               Run.run(spec, ["hi"], to: "b")

      assert {:error, {:unknown_route, "z", ["a", "b"]}} = Run.run(spec, ["hi"], to: "z")
    end

    test "consensus converges on the parsed verdict" do
      spec = %{
        "pattern" => "consensus",
        "agents" => [@echo, @echo, @echo],
        "verdicts" => ["approve", "reject"]
      }

      assert {:ok, %{results: [%{status: :completed, text: text}]}} =
               Run.run(spec, ["Ship?\nVERDICT: approve"])

      assert text =~ "APPROVE"
    end

    test "a run that outlives its timeout is reported and its instance stopped" do
      spec = %{"pattern" => "solo", "agent" => @echo}
      assert {:ok, %{results: [item], instance: name}} = Run.run(spec, ["x"], timeout: 0)
      assert item.status in [:timeout, :completed]
      assert_stopped(name)
    end
  end

  # stop_instance/1 is synchronous, but Registry entries are removed
  # asynchronously (genagent/gen_agent_server#26).
  defp assert_stopped(name, attempts \\ 50) do
    cond do
      name not in GenAgentServer.instances() -> :ok
      attempts == 0 -> flunk("instance #{name} still registered")
      true -> Process.sleep(10) && assert_stopped(name, attempts - 1)
    end
  end
end

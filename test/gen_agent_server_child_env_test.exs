defmodule GenAgentServer.ChildEnvTest do
  # Mutates the test VM environment with fake release variables in one group
  # and `:provider_overrides` in another, so this file must not run async.
  use ExUnit.Case, async: false

  alias GenAgentServer.{ChildEnv, Providers}

  # Variable names only; the fake values below are never real credentials.
  @fake_cookie "RELEASE_COOKIE"
  @fake_auth "GEN_AGENT_TEST_FAKE_AUTH"

  @release_root "/opt/fake-release"

  defp release_parent(extra \\ %{}) do
    Map.merge(
      %{
        "RELEASE_ROOT" => @release_root,
        "RELEASE_NODE" => "fake-node",
        @fake_cookie => "fake-cookie-value",
        "BINDIR" => "#{@release_root}/erts-15.2/bin",
        "ROOTDIR" => @release_root,
        "PATH" =>
          Enum.join(
            [
              "#{@release_root}/erts-15.2/bin",
              "#{@release_root}/bin",
              "/opt/homebrew/bin",
              "#{@release_root}/bin-tools",
              "#{@release_root}/bin/extra",
              "#{@release_root}/erts-15.2/bin/deeper",
              "/usr/bin"
            ],
            ":"
          ),
        @fake_auth => "fake-token-value",
        "HOME" => "/Users/fake"
      },
      extra
    )
  end

  # Env entries use string names, so plain Keyword access does not apply.
  defp get(env, name) do
    case List.keyfind(env, name, 0) do
      {^name, value} -> value
      nil -> :missing
    end
  end

  describe "normalize/2" do
    test "unsets release boot variables and strips only release PATH entries" do
      env = ChildEnv.normalize([], release_parent())

      assert get(env, @fake_cookie) == false
      assert get(env, "RELEASE_ROOT") == false
      assert get(env, "RELEASE_NODE") == false
      assert get(env, "BINDIR") == false
      assert get(env, "ROOTDIR") == false

      assert get(env, "PATH") ==
               Enum.join(
                 [
                   "/opt/homebrew/bin",
                   "#{@release_root}/bin-tools",
                   "#{@release_root}/bin/extra",
                   "#{@release_root}/erts-15.2/bin/deeper",
                   "/usr/bin"
                 ],
                 ":"
               )

      # Unrelated variables are neither copied nor unset.
      assert get(env, @fake_auth) == :missing
      assert get(env, "HOME") == :missing
      names = Enum.map(env, &elem(&1, 0))
      assert names == Enum.sort(names)
    end

    test "ordinary developer launch leaves PATH alone and only unsets boot names" do
      parent = %{"PATH" => "/opt/homebrew/bin:/usr/bin", "HOME" => "/Users/fake"}

      assert ChildEnv.normalize([], parent) == [{"BINDIR", false}, {"ROOTDIR", false}]
    end

    test "trusted overrides win except for release boot names and PATH cleanup" do
      overrides = %{
        "CUSTOM_FLAG" => "on",
        :TO_UNSET => false,
        "RELEASE_SNEAKY" => "x",
        "BINDIR" => "/somewhere",
        "PATH" => "/custom/bin:#{@release_root}/bin:#{@release_root}/erts-15.2/bin"
      }

      env = ChildEnv.normalize(overrides, release_parent())

      assert get(env, "CUSTOM_FLAG") == "on"
      assert get(env, "TO_UNSET") == false
      assert get(env, "RELEASE_SNEAKY") == false
      assert get(env, "BINDIR") == false
      assert get(env, "PATH") == "/custom/bin"
      assert get(env, @fake_cookie) == false
    end

    test "an override PATH is kept even when clean, and PATH=false stays unset" do
      assert get(ChildEnv.normalize(%{"PATH" => "/a:/b"}, release_parent()), "PATH") == "/a:/b"
      assert get(ChildEnv.normalize(%{"PATH" => false}, release_parent()), "PATH") == false
    end

    test "rejects malformed override entries" do
      assert_raise ArgumentError, fn -> ChildEnv.normalize(%{"X" => 1}, %{}) end
      assert_raise ArgumentError, fn -> ChildEnv.normalize([{"X", nil}], %{}) end

      error =
        assert_raise ArgumentError, fn ->
          ChildEnv.normalize(["private-value-must-not-appear"], %{})
        end

      refute Exception.message(error) =~ "private-value-must-not-appear"
    end
  end

  describe "backend options" do
    setup do
      previous = Application.get_env(:gen_agent_server, :provider_overrides)

      on_exit(fn ->
        if previous,
          do: Application.put_env(:gen_agent_server, :provider_overrides, previous),
          else: Application.delete_env(:gen_agent_server, :provider_overrides)
      end)

      :ok
    end

    test "Providers adds env to CLI backends only" do
      assert {:ok, claude} = Providers.backend_opts("claude", cwd: File.cwd!())
      assert {:ok, codex} = Providers.backend_opts("codex", cwd: File.cwd!())
      assert {:ok, echo} = Providers.backend_opts("echo")

      for opts <- [claude, codex] do
        assert {"BINDIR", false} in opts[:env]
        assert {"ROOTDIR", false} in opts[:env]

        assert Enum.all?(opts[:env], fn {name, value} ->
                 is_binary(name) and (is_binary(value) or value == false)
               end)
      end

      refute Keyword.has_key?(echo, :env)
    end

    test "override env merges under cleanup; replacement backends get no env" do
      Application.put_env(:gen_agent_server, :provider_overrides, %{
        "claude" => [env: %{"CUSTOM" => "1", "RELEASE_X" => "no"}, model: "override-model"],
        "codex" => [backend: GenAgentEnsemble.Backends.Echo]
      })

      assert {:ok, claude} = Providers.backend_opts("claude", cwd: File.cwd!())
      assert claude[:model] == "override-model"
      assert get(claude[:env], "CUSTOM") == "1"
      assert get(claude[:env], "RELEASE_X") == false

      assert {:ok, codex} = Providers.backend_opts("codex", cwd: File.cwd!())
      assert codex[:backend] == GenAgentEnsemble.Backends.Echo
      refute Keyword.has_key?(codex, :env)
    end

    test "harden_agents covers runtime.exs-shaped tuples and is idempotent" do
      agents = [
        {"echo", GenAgentEnsemble.Agents.Simple, [backend: GenAgentEnsemble.Backends.Echo]},
        {"claude", GenAgentEnsemble.Agents.Simple,
         [backend: GenAgent.Backends.Claude, working_dir: ".", permission_mode: :plan]},
        {"codex", GenAgentEnsemble.Agents.Simple,
         [backend: GenAgent.Backends.Codex, working_dir: ".", env: [{"KEEP", "1"}]]},
        {:custom, :shape}
      ]

      [echo, claude, codex, custom] = hardened = ChildEnv.harden_agents(agents)

      assert echo == hd(agents)
      assert custom == {:custom, :shape}
      assert {"BINDIR", false} in elem(claude, 2)[:env]
      assert elem(claude, 2)[:permission_mode] == :plan
      assert get(elem(codex, 2)[:env], "KEEP") == "1"
      assert {"ROOTDIR", false} in elem(codex, 2)[:env]
      assert ChildEnv.harden_agents(hardened) == hardened
    end

    test "start_instance hands the real Claude backend a normalized env" do
      name = "child-env-#{System.unique_integer([:positive])}"
      test_pid = self()

      stream_fn = fn _prompt, opts ->
        send(test_pid, {:claude_stream_opts, opts})
        []
      end

      agents = [
        {"claude", GenAgentEnsemble.Agents.Simple,
         [
           backend: GenAgent.Backends.Claude,
           working_dir: File.cwd!(),
           permission_mode: :plan,
           stream_fn: stream_fn
         ]}
      ]

      assert {:ok, _pid} = GenAgentServer.start_instance(name, agents)
      on_exit(fn -> GenAgentServer.stop_instance(name) end)

      assert {:ok, _id} = GenAgentServer.invoke(name, "claude", "hi")
      assert_receive {:claude_stream_opts, opts}, 5_000
      assert {"BINDIR", false} in opts[:env]
      assert {"ROOTDIR", false} in opts[:env]
    end
  end

  describe "default runners" do
    setup do
      suffix = System.unique_integer([:positive])
      dir = Path.join(System.tmp_dir!(), "gen-agent-child-env-#{suffix}")
      File.mkdir_p!(dir)
      probe = Path.join(dir, "env-probe.sh")

      # Prints presence of each named variable, never a value. PATH is echoed
      # only when the caller opts in with GEN_AGENT_PROBE_PATH.
      File.write!(probe, """
      #!/bin/sh
      for name in "$@"; do
        if eval "[ \\"\\${$name+set}\\" = set ]"; then
          echo "present $name"
        else
          echo "absent $name"
        fi
      done
      if [ "${GEN_AGENT_PROBE_PATH:-}" = "1" ]; then
        echo "path $PATH"
      fi
      """)

      File.chmod!(probe, 0o755)

      fakes = %{
        "RELEASE_GEN_AGENT_TEST" => "fake",
        "BINDIR" => dir,
        @fake_auth => "fake",
        "GEN_AGENT_SERVER_SHARED_MCP_TOKEN" => "fake-shared-token"
      }

      previous = Map.new(fakes, fn {name, _} -> {name, System.get_env(name)} end)
      Enum.each(fakes, fn {name, value} -> System.put_env(name, value) end)

      on_exit(fn ->
        Enum.each(previous, fn
          {name, nil} -> System.delete_env(name)
          {name, value} -> System.put_env(name, value)
        end)

        File.rm_rf!(dir)
      end)

      %{probe: probe}
    end

    @names [
      "RELEASE_GEN_AGENT_TEST",
      "BINDIR",
      "ROOTDIR",
      @fake_auth,
      "CUSTOM_FLAG",
      "GEN_AGENT_SERVER_SHARED_MCP_TOKEN"
    ]

    defp claude_lines(probe, args, env) do
      probe
      |> ClaudeWrapper.Runner.Port.stream_lines(args, [env: env], 5_000)
      |> Enum.to_list()
    end

    defp codex_lines(probe, args, env) do
      {:ok, {out, 0}} = CodexWrapper.Runner.Port.run(probe, args, [env: env], 5_000)
      String.split(out, "\n", trim: true)
    end

    test "both runners unset release variables and keep the rest", %{probe: probe} do
      env = ChildEnv.normalize(%{"CUSTOM_FLAG" => "on"})

      for lines <- [claude_lines(probe, @names, env), codex_lines(probe, @names, env)] do
        assert "absent RELEASE_GEN_AGENT_TEST" in lines
        assert "absent BINDIR" in lines
        assert "absent ROOTDIR" in lines
        assert "absent GEN_AGENT_SERVER_SHARED_MCP_TOKEN" in lines
        assert "present #{@fake_auth}" in lines
        assert "present CUSTOM_FLAG" in lines
      end
    end

    test "without normalization the child inherits release variables", %{probe: probe} do
      lines = codex_lines(probe, ["RELEASE_GEN_AGENT_TEST", "BINDIR"], [])
      assert "present RELEASE_GEN_AGENT_TEST" in lines
      assert "present BINDIR" in lines
    end

    test "child PATH drops release entries and keeps lookalikes", %{probe: probe} do
      env = ChildEnv.normalize(%{"GEN_AGENT_PROBE_PATH" => "1"}, release_parent())
      expected = "path " <> get(env, "PATH")

      assert expected in claude_lines(probe, [], env)
      assert expected in codex_lines(probe, [], env)
      assert String.contains?(expected, "#{@release_root}/bin-tools")
      refute String.contains?(expected, "#{@release_root}/bin:")
    end
  end
end

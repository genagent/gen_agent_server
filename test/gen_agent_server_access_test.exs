defmodule GenAgentServer.AccessTest do
  use ExUnit.Case, async: false
  alias GenAgentServer.{InstanceSpec, Profiles, Providers, RuntimeConfig}

  @modes [:inherit, :read_only, :plan, :accept_edits, :auto, :bypass_permissions, :dont_ask]

  setup do
    previous = Application.fetch_env(:gen_agent_server, :provider_overrides)
    Application.delete_env(:gen_agent_server, :provider_overrides)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:gen_agent_server, :provider_overrides, value)
        :error -> Application.delete_env(:gen_agent_server, :provider_overrides)
      end
    end)

    :ok
  end

  test "omission and explicit inheritance omit access overrides" do
    for provider <- ["claude", "codex"] do
      assert {:ok, defaults} = Providers.backend_opts(provider, cwd: File.cwd!())

      assert {:ok, ^defaults} =
               Providers.backend_opts(provider,
                 cwd: File.cwd!(),
                 claude_permission_mode: :inherit,
                 codex_sandbox: :inherit,
                 codex_user_config: :inherit
               )

      for key <- [:sandbox, :permission_mode, :tools, :ignore_user_config] do
        refute Keyword.has_key?(defaults, key)
      end

      if provider == "codex", do: assert(defaults[:approval_policy] == :never)
    end
  end

  test "explicit access modes retain their individual mappings and descriptions" do
    for mode <- @modes do
      assert {:ok, opts} =
               Providers.backend_opts("claude", cwd: File.cwd!(), claude_permission_mode: mode)

      case mode do
        :inherit ->
          refute Keyword.has_key?(opts, :permission_mode)

        :read_only ->
          assert opts[:permission_mode] == :dont_ask
          assert opts[:tools] == ["Read", "Grep", "Glob"]

        mode ->
          assert opts[:permission_mode] == mode
          refute Keyword.has_key?(opts, :tools)
      end

      assert {:ok, parsed} =
               InstanceSpec.parse("access", %{
                 "cwd" => File.cwd!(),
                 "routes" => [
                   %{
                     "name" => "c",
                     "provider" => "claude",
                     "claude_permission_mode" => Atom.to_string(mode)
                   }
                 ]
               })

      assert hd(parsed.description.routes).claude_permission_mode == mode
      assert hd(parsed.description.routes).review_read_only_explicit == (mode == :read_only)
    end

    for sandbox <- [:inherit, :read_only, :workspace_write], config <- [:inherit, :ignore] do
      assert {:ok, opts} =
               Providers.backend_opts("codex",
                 cwd: File.cwd!(),
                 codex_sandbox: sandbox,
                 codex_user_config: config
               )

      assert opts[:sandbox] == if(sandbox == :inherit, do: nil, else: sandbox)
      assert opts[:ignore_user_config] == if(config == :ignore, do: true, else: nil)
    end

    for {provider, key} <- [
          {"claude", :claude_permission_mode},
          {"codex", :codex_sandbox},
          {"codex", :codex_user_config}
        ] do
      for invalid <- [:unknown, "inherit", nil] do
        assert {:error, {:invalid_option, ^key, ^invalid}} =
                 Providers.backend_opts(provider, [{:cwd, File.cwd!()}, {key, invalid}])
      end
    end
  end

  test "startup defaults match shared defaults and validate providers and cwd" do
    assert [{"echo", _, _}] = RuntimeConfig.from_env!(%{})[:agents]

    for provider <- Providers.names() do
      assert [{^provider, GenAgentEnsemble.Agents.Simple, opts}] =
               RuntimeConfig.from_env!(%{"GEN_AGENT_SERVER_PROVIDERS" => provider})[:agents]

      assert {:ok, shared} = Providers.backend_opts(provider, cwd: File.cwd!())
      assert GenAgentServer.ChildEnv.harden_backend_opts(opts) == shared
    end

    assert_raise ArgumentError, "unknown provider: invalid", fn ->
      RuntimeConfig.from_env!(%{"GEN_AGENT_SERVER_PROVIDERS" => "invalid"})
    end

    assert_raise ArgumentError, fn ->
      RuntimeConfig.from_env!(%{"GEN_AGENT_SERVER_CWD" => "/nonexistent/access-test"})
    end
  end

  test "startup construction skips provider overrides and defers child environment hardening" do
    before = RuntimeConfig.from_env!(%{"GEN_AGENT_SERVER_PROVIDERS" => "claude,codex"})

    Application.put_env(:gen_agent_server, :provider_overrides, %{
      "claude" => [permission_mode: :accept_edits, env: %{"STARTUP_OVERRIDE" => "yes"}],
      "codex" => [sandbox: :workspace_write, ignore_user_config: true]
    })

    assert RuntimeConfig.from_env!(%{"GEN_AGENT_SERVER_PROVIDERS" => "claude,codex"}) == before
    for {_, _, opts} <- before[:agents], do: refute(Keyword.has_key?(opts, :env))
    assert {:ok, claude} = Providers.backend_opts("claude", cwd: File.cwd!())
    assert claude[:permission_mode] == :accept_edits
    assert {:ok, codex} = Providers.backend_opts("codex", cwd: File.cwd!())
    assert codex[:sandbox] == :workspace_write
    assert codex[:ignore_user_config]
  end

  test "configured dynamic descriptions report every selected access mode" do
    name = "access-#{System.unique_integer([:positive])}"
    on_exit(fn -> GenAgentServer.stop_instance(name) end)

    routes =
      Enum.map(@modes, fn mode ->
        %{
          "name" => Atom.to_string(mode),
          "provider" => "claude",
          "claude_permission_mode" => Atom.to_string(mode)
        }
      end) ++
        Enum.map(["inherit", "read_only", "workspace_write"], fn sandbox ->
          %{"name" => "codex-" <> sandbox, "provider" => "codex", "codex_sandbox" => sandbox}
        end)

    assert {:ok, _} =
             GenAgentServer.Ops.call("create_instance", %{
               "instance" => name,
               "config" => %{"cwd" => File.cwd!(), "routes" => routes}
             })

    assert {:ok, description} =
             GenAgentServer.Ops.call("describe_instance", %{"instance" => name})

    assert Enum.map(description["routes"], & &1["claude_permission_mode"])
           |> Enum.take(length(@modes)) == Enum.map(@modes, &Atom.to_string/1)

    for route <- Enum.drop(description["routes"], length(@modes)) do
      assert route["codex_sandbox"] == String.replace_prefix(route["name"], "codex-", "")
      assert route["codex_user_config"] == "inherit"
    end
  end

  test "operation schema exposes every supported access value" do
    {:ok, op} = GenAgentServer.Ops.fetch("create_instance")
    schema = GenAgentServer.Ops.json_schema(op)
    props = schema["properties"]["config"]["properties"]["routes"]["items"]["properties"]
    assert props["claude_permission_mode"]["enum"] == Enum.map(@modes, &Atom.to_string/1)
    assert props["codex_sandbox"]["enum"] == ["inherit", "read_only", "workspace_write"]
    assert props["codex_user_config"]["enum"] == ["inherit", "ignore"]
  end

  test "profiles accept inherited defaults and all Claude modes" do
    path =
      Path.join(System.tmp_dir!(), "access-profiles-#{System.unique_integer([:positive])}.json")

    on_exit(fn -> File.rm(path) end)

    for mode <- [nil | @modes] do
      profile = %{"name" => "access", "cwd" => File.cwd!(), "providers" => ["claude", "codex"]}

      profile =
        if mode,
          do: Map.put(profile, "claude_permission_mode", Atom.to_string(mode)),
          else: profile

      File.write!(path, Jason.encode!(%{"profiles" => [profile]}))
      assert [{"access", [{"claude", _, claude}, {"codex", _, codex}]}] = Profiles.load!(path)

      assert {:ok, ^claude} =
               Providers.backend_opts("claude",
                 cwd: File.cwd!(),
                 claude_permission_mode: mode || :inherit
               )

      refute Keyword.has_key?(codex, :sandbox)
      refute Keyword.has_key?(codex, :ignore_user_config)
    end
  end
end

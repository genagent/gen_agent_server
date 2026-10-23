defmodule OperatorView.OperatorCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  import ExUnit.Assertions

  @restored [
    :instances,
    :transport,
    :token,
    :release_bin,
    :rpc_timeout_ms,
    :refresh_interval_ms,
    :refresh_deadline_ms,
    :in_process_owner
  ]

  using do
    quote do
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import Plug.Conn
      import OperatorView.OperatorCase

      @endpoint OperatorViewWeb.Endpoint
    end
  end

  setup do
    saved = for key <- @restored, do: {key, Application.fetch_env(:operator_view, key)}
    on_exit(fn -> Enum.each(saved, &restore/1) end)
    :ok
  end

  defp restore({key, {:ok, value}}), do: Application.put_env(:operator_view, key, value)
  defp restore({key, :error}), do: Application.delete_env(:operator_view, key)

  @doc "Set observer settings for one test; they are restored afterwards."
  def configure(settings) do
    Enum.each(settings, fn {key, value} -> Application.put_env(:operator_view, key, value) end)
  end

  @doc "A loopback request without an operator session."
  def loopback_conn, do: Map.put(Phoenix.ConnTest.build_conn(), :host, "127.0.0.1")

  @doc "A loopback request with a valid operator session."
  def operator_conn do
    marker = OperatorViewWeb.OperatorAuth.session_marker()
    Plug.Test.init_test_session(loopback_conn(), %{"operator_view_auth" => marker})
  end

  @doc "Operations the transport reported, in order, until it is quiet for `timeout` ms."
  def drain_calls(timeout \\ 150) do
    receive do
      {:release_call, operation, args} -> [{operation, args} | drain_calls(timeout)]
    after
      timeout -> []
    end
  end

  @doc "Assert every reported operation was a fixed read scoped to an allowlisted instance."
  def assert_only_reads(allowed) do
    calls = drain_calls()
    operations = OperatorView.Reader.operations()
    assert Enum.all?(calls, fn {operation, _args} -> operation in operations end)
    assert Enum.all?(calls, fn {_operation, args} -> args["instance"] in [nil | allowed] end)
    calls
  end

  def eventually(fun, attempts \\ 200) do
    cond do
      fun.() -> true
      attempts == 0 -> false
      true -> Process.sleep(10) && eventually(fun, attempts - 1)
    end
  end

  @doc "A retained summary as the release's Ops envelope encodes it."
  def summary(id, status) do
    terminal? = status != "pending"

    %{
      "id" => id,
      "route" => "worker",
      "source" => "api",
      "status" => status,
      "admitted_at_unix_ms" => 1_792_000_000_000,
      "completed_at_unix_ms" => if(terminal?, do: 1_792_000_000_500),
      "duration_ms" => if(terminal?, do: 500),
      "error_category" => nil
    }
  end

  @doc "Ops data for one raw (not create_instance) instance in a FakeRelease."
  def instance_data(name, summaries) do
    %{
      "describe_instance" => %{
        "instance" => name,
        "configured" => false,
        "routes" => [%{"name" => "worker"}],
        "strategy" => "GenAgentEnsemble.Strategies.Switchboard",
        "limits" => %{"max_in_flight" => 16, "max_results" => 100}
      },
      "status" => %{
        "strategy" => "GenAgentEnsemble.Strategies.Switchboard",
        "routes" => ["worker"],
        "agents" => ["worker"]
      },
      "invocations" => %{"instance" => name, "invocations" => summaries}
    }
  end
end

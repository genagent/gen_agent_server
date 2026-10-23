defmodule OperatorView.AuthTest do
  use OperatorView.OperatorCase, async: false

  alias OperatorView.{FakeRelease, WebSocketClient}

  setup do
    data = %{"alpha" => instance_data("alpha", [])}
    start_supervised!({FakeRelease, owner: self(), instances: ["alpha"], data: data})
    configure(transport: FakeRelease, instances: ["alpha"])
    :ok
  end

  defp follow(conn), do: conn |> recycle() |> Map.put(:host, "127.0.0.1")

  # A browser-like request: loopback host, cookies carried over from the
  # previous response, and CSRF protection enforced. Phoenix.ConnTest skips
  # CSRF checks unless :plug_skip_csrf_protection is removed.
  defp browser(previous \\ nil) do
    conn = if previous, do: recycle(previous), else: Phoenix.ConnTest.build_conn()
    %{conn | host: "127.0.0.1", private: Map.delete(conn.private, :plug_skip_csrf_protection)}
  end

  defp csrf_token(html) do
    [token] = Regex.run(~r/name="_csrf_token" value="([^"]+)"/, html, capture: :all_but_first)
    token
  end

  defp token, do: Application.fetch_env!(:operator_view, :token)

  defp log_in do
    form = get(browser(), "/login")
    params = %{"_csrf_token" => csrf_token(html_response(form, 200)), "token" => token()}
    conn = post(browser(form), "/login", params)
    assert redirected_to(conn) == "/"
    conn
  end

  test "the HTTP page and its disconnected live render require an operator session" do
    assert redirected_to(get(loopback_conn(), "/")) == "/login"
    assert {:error, {:redirect, %{to: "/login"}}} = live(loopback_conn(), "/")

    forged = Plug.Test.init_test_session(loopback_conn(), %{"operator_view_auth" => "forged"})
    assert redirected_to(get(forged, "/")) == "/login"
    assert {:error, {:redirect, %{to: "/login"}}} = live(forged, "/")
  end

  # live/1 on an already rendered response skips the HTTP pipeline and only
  # runs the connected mount, so this exercises on_mount's own check.
  test "a rendered page whose session became invalid is refused when it connects" do
    page = get(operator_conn(), "/?instance=alpha")
    assert html_response(page, 200) =~ "data-phx-session"
    assert {:ok, _view, _html} = live(page)

    configure(token: token() <> "-rotated")
    assert {:error, {:redirect, %{to: "/login"}}} = live(page)
  end

  test "only the configured token logs in, and rotating it ends the session" do
    form = get(browser(), "/login")
    csrf = csrf_token(html_response(form, 200))

    rejected = post(browser(form), "/login", %{"_csrf_token" => csrf, "token" => "wrong-token"})
    assert html_response(rejected, 401) =~ "Token not accepted."
    refute get_session(rejected, "operator_view_auth")
    refute html_response(rejected, 401) =~ token()

    logged_in = log_in()
    page = get(browser(logged_in), "/")
    assert html_response(page, 200) =~ "gen_agent_server operator view"

    configure(token: token() <> "-rotated")
    assert redirected_to(get(browser(logged_in), "/")) == "/login"
  end

  test "logging in requires the CSRF token of the login form's session" do
    form = get(browser(), "/login")
    other_session = csrf_token(html_response(get(browser(), "/login"), 200))

    for csrf <- [%{}, %{"_csrf_token" => "forged"}, %{"_csrf_token" => other_session}] do
      params = Map.put(csrf, "token", token())
      assert_error_sent(403, fn -> post(browser(form), "/login", params) end)
    end

    assert redirected_to(get(browser(form), "/")) == "/login"
  end

  test "logging out requires a CSRF token and then drops the session" do
    page = get(browser(log_in()), "/")
    csrf = csrf_token(html_response(page, 200))

    assert_error_sent(403, fn -> post(browser(page), "/logout", %{}) end)
    assert_error_sent(403, fn -> post(browser(page), "/logout", %{"_csrf_token" => "forged"}) end)
    assert html_response(get(browser(page), "/"), 200) =~ "gen_agent_server operator view"

    conn = post(browser(page), "/logout", %{"_csrf_token" => csrf})
    assert redirected_to(conn) == "/login"
    assert redirected_to(get(follow(conn), "/")) == "/login"
  end

  test "requests that do not name a loopback host are refused" do
    assert response(get(Phoenix.ConnTest.build_conn(), "/login"), 400)
    assert response(get(Map.put(loopback_conn(), :host, "rebound.example"), "/login"), 400)
    assert response(get(Map.put(operator_conn(), :remote_ip, {10, 0, 0, 2}), "/"), 400)
  end

  test "pages never show the token or the release path" do
    configure(release_bin: "/secret/release/bin/gen_agent_server")

    for conn <- [get(loopback_conn(), "/login"), get(operator_conn(), "/")] do
      html = html_response(conn, 200)
      refute html =~ token()
      refute html =~ "/secret/release"
    end
  end

  # What the browser holds after loading the page: its session cookie, the
  # page's CSRF token and the LiveView's signed session and static tokens.
  defp rendered_page do
    page = get(browser(log_in()), "/?instance=alpha")
    html = html_response(page, 200)
    [main] = Regex.run(~r/<div[^>]*data-phx-main[^>]*>/, html)
    attribute = fn name -> Regex.run(~r/\s#{name}="([^"]+)"/, main, capture: :all_but_first) end

    cookies = page |> browser() |> fetch_cookies() |> Map.fetch!(:req_cookies)
    [csrf] = Regex.run(~r/name="csrf-token" content="([^"]+)"/, html, capture: :all_but_first)

    %{
      cookie: Map.fetch!(cookies, "_operator_view"),
      csrf: csrf,
      id: hd(attribute.("id")),
      session: hd(attribute.("data-phx-session")),
      static: hd(attribute.("data-phx-static"))
    }
  end

  defp connect(port, origin, query, cookie) do
    headers = [{"origin", origin}] ++ if(cookie, do: [{"cookie", cookie}], else: [])
    WebSocketClient.upgrade(port, "/live/websocket?" <> URI.encode_query(query), headers)
  end

  # Join the page's LiveView as the browser's LiveSocket would and return the
  # join reply.
  defp join(port, page, opts) do
    csrf = Keyword.get(opts, :csrf, page.csrf)
    cookie = if Keyword.get(opts, :cookie, true), do: "_operator_view=" <> page.cookie
    query = %{"_csrf_token" => csrf, "vsn" => "2.0.0"}
    {101, client} = connect(port, "http://127.0.0.1:#{port}", query, cookie)

    payload = %{
      "url" => "http://127.0.0.1:#{port}/?instance=alpha",
      "params" => %{"_csrf_token" => csrf, "_mounts" => 0},
      "session" => page.session,
      "static" => page.static
    }

    WebSocketClient.send_json(client, ["1", "1", "lv:" <> page.id, "phx_join", payload])

    {[_join_ref, "1", _topic, "phx_reply", reply], client} =
      WebSocketClient.receive_json(client, &match?([_, "1", _, "phx_reply", _], &1))

    WebSocketClient.close(client)
    reply
  end

  describe "the live socket over a real listener" do
    setup do
      opts = [plug: OperatorViewWeb.Endpoint, ip: {127, 0, 0, 1}, port: 0, startup_log: false]
      server = start_supervised!({Bandit, opts})
      {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
      {:ok, port: port}
    end

    test "an upgrade from another origin is refused", %{port: port} do
      query = %{"vsn" => "2.0.0"}

      for origin <- ["http://rebound.example", "http://rebound.example:#{port}"] do
        assert {403, client} = connect(port, origin, query, nil)
        WebSocketClient.close(client)
      end

      assert {101, client} = connect(port, "http://127.0.0.1:#{port}", query, nil)
      WebSocketClient.close(client)
    end

    test "joining needs the page's CSRF token and the operator session", %{port: port} do
      page = rendered_page()
      assert %{"status" => "ok", "response" => %{"rendered" => _}} = join(port, page, [])

      for opts <- [[csrf: "forged"], [csrf: rendered_page().csrf], [cookie: false]] do
        assert %{"status" => "error", "response" => %{"reason" => "stale"}} =
                 join(port, page, opts)
      end
    end

    test "a reconnect after the token rotates is redirected to login", %{port: port} do
      page = rendered_page()
      assert %{"status" => "ok"} = join(port, page, [])

      configure(token: token() <> "-rotated")

      assert %{"status" => "error", "response" => %{"redirect" => %{"to" => "/login"}}} =
               join(port, page, [])
    end
  end
end

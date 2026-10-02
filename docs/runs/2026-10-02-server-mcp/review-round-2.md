I’ll read the adapter, Ops, tests, and startup configuration, then check compatibility and scope without fetching dependencies or changing files.


The six-tool allowlist is correctly wired to Ops. I’m checking the published Snodo callback contract and startup path; both could prevent the server from working despite the catalogue being correct.


REQUEST CHANGES

- **[P1] Every dispatched tool returns an invalid Snodo callback result** — `lib/gen_agent_server/mcp.ex:30`: Both branches return bare `%Snodo.Result{}` structs. Snodo 0.4.0 requires `{:ok, result}`; its router converts these bare returns into `-32603 “Tool returned an invalid result”`. Wrap both successful results and domain-error results in `{:ok, ...}`.

- **[P1] Mix entry point skips runtime configuration** — `lib/mix/tasks/gen_agent_server.mcp.ex:18`: `compile` does not load `config/runtime.exs`. Consequently, `serve/0` starts the application without its required `:session_name` and `:agents` configuration, and startup fails. Run `app.config` before `serve/0`, retaining Logger redirection before application startup.

- **[P2] Discovery test assumes the wrong client return shape** — `test/gen_agent_server_mcp_test.exs:15`: Published Snodo 0.4.0 `Client.list_tools/1` returns `{:ok, tools_list}`, not a map containing `"tools"`. Passing that list to `field/3` raises `BadMapError`. Assert directly against the returned list.

- **[P2] Missing-argument assertion cannot pass** — `test/gen_agent_server_mcp_test.exs:65`: Snodo validates required arguments before calling Ops. This request produces `"Missing required arguments: prompt"`, without `"invalid_args"`. Assert Snodo’s actual error behavior here; retain separate assertions for Ops validation.

- **[P2] MCP advertises the release version prematurely** — `lib/gen_agent_server/mcp/server.ex:6`: The server reports `"0.1.0"` despite the explicit requirement to retain `"0.1.0-dev"`. Keep the MCP server version aligned with the project version.

Verified Snodo behavior against release commit `442b0da`, read locally. Full compilation and tests were not run; the checkout lacks the Snodo dependency.
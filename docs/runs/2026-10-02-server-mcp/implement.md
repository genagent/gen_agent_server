I fixed all five findings. Nothing was compiled or run in this pass; the caller will run format, compile and tests.

Files changed:
- `lib/gen_agent_server/mcp.ex`
- `lib/mix/tasks/gen_agent_server.mcp.ex`
- `lib/gen_agent_server/mcp/server.ex`
- `test/gen_agent_server_mcp_test.exs`

- **[P1] Invalid callback result:** fixed. `MCP.run/2` now returns `{:ok, Snodo.Result...}` for both the structured success and the domain-error result.
- **[P1] Mix skips runtime config:** fixed. The task now runs `app.config` instead of `compile`. That compiles and loads `config/runtime.exs` without starting the app, so `serve/0` still redirects Logger to stderr before startup. I also removed the "run `mix compile` once first" line from the task doc.
- **[P2] Discovery test shape:** fixed. The test now uses the list from `list_tools/1` directly. This matches the 0.4.0 `list_all` implementation.
- **[P2] Missing-argument assertion:** fixed. The test now expects Snodo's `"Missing required arguments: prompt"`, which comes back as an `isError` result. The other two assertions stay, because the default passthrough validator lets `bogus` and `source` reach Ops, which returns `invalid_args`.
- **[P2] Advertised version:** fixed. The server sets `@version Mix.Project.config()[:version]` at compile time, which `use Snodo.Server` accepts as a module attribute. It advertises `0.1.0-dev` and follows the project version, and it works in a release because the value is fixed at compile time.

The README still tells users to run `mix compile` once before registering the command. That is harmless, so I left it.
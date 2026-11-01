CI's mcp job runs MIX_ENV=prod mix release and then MIX_ENV=prod mix run examples/mcp_release_smoke.exs in extensions/mcp. It fails with:

    ** (RuntimeError) MCP quickstart is incomplete
        examples/mcp_release_smoke.exs:37

Line 36 checks the quickstart resource for `to a read-only sandbox`, which described the old default. Your quickstart change in extensions/mcp/lib/gen_agent_server/mcp/resources.ex correctly says CLI routes default to `inherit`. Change only the smoke assertion so it checks for `create_instance` and for the new default statement in the quickstart text (match a phrase that is actually in the new quickstart). Also search extensions/mcp/examples and the root examples/ for any other assertion on the old default wording and update it the same way. Report each line you changed. The operator runs the release smoke.

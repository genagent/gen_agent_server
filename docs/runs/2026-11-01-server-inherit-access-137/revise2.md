I’ll check both example directories for assertions on the old default, update the smoke assertion, and report each changed line.

Changed only line 36 of [mcp_release_smoke.exs](/Users/joshrotenberg/Code/github.com/genagent/gen_agent_server-137/extensions/mcp/examples/mcp_release_smoke.exs:36): it now checks for both `create_instance` and `CLI routes default to `inherit``, matching the quickstart.

Searched both example directories; no other assertions use the old default wording. `git diff --check` passed. Release smoke left to the operator.

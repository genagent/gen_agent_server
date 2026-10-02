# Work-machine MCP readiness probe (2026-10-02)

The isolated clone `/tmp/gen_agent_server_readiness_20261002` started at server
`main` `5225b85`. `mix deps.get` selected `gen_agent_codex 0.4.3` and
`codex_wrapper 0.5.4`, missing the published #123/#124 fixes. A targeted
`mix deps.update gen_agent_codex codex_wrapper` selected 0.4.5 and 0.5.5.
No other lock entries changed. [PR #79](https://github.com/genagent/gen_agent_server/pull/79)
merged as `e88d46b`; its post-merge CI passed. The server version remains
0.1.0, so the existing v0.1.0 tag predates this lock correction.

Host checks on the updated lock: `mix test` (71 tests),
`MIX_ENV=prod mix release --overwrite`, and
`MIX_ENV=prod mix run examples/mcp_release_smoke.exs` all passed. The packaged
release binary used for the following probes was
`/tmp/gen_agent_server_readiness_20261002/_build/prod/rel/gen_agent_server/bin/gen_agent_server`.

## CLI client probes

The exact Codex task prompt was:

> Use the gen_agent_server MCP tools to list instances, invoke the echo agent with work-machine-smoke, then read its result and report it. Do not use shell tools.

The client was `codex exec --json --ephemeral --ignore-user-config
--skip-git-repo-check --sandbox read-only -m gpt-6-luna`. Its temporary
command-line config set
`mcp_servers.gen_agent_server.command` to the packaged binary and
`mcp_servers.gen_agent_server.args` to
`["eval", "GenAgentServer.MCP.serve()"]`; no saved Codex config was edited.
The first run left tool approval at its default and `instances` failed with
`MCP tool call requires approval, but approval policy is never`. A second run
set `mcp_servers.gen_agent_server.default_tools_approval_mode="auto"`; the
same call still failed. The successful run set
`mcp_servers.gen_agent_server.tools.{instances,invoke,result}.approval_mode`
to `"approve"` for this Echo-only probe. It returned `server/default`,
`inv-2`, and `echo: work-machine-smoke`. The model also tried `agents`, which
was denied because that tool had not been approved; this did not prevent the
requested task. The approval is appropriate only to this bounded probe;
work-starting tools should retain a deliberate policy in ordinary use.

The exact Claude task prompt was:

> Use the gen_agent_server MCP tools to list instances, invoke echo with claude-work-machine-smoke, then read its result. Report it briefly. Do not use shell tools.

The client was `claude -p --verbose --model haiku --max-budget-usd 0.25
--no-session-persistence --strict-mcp-config --permission-mode dontAsk
--output-format stream-json` with a temporary `--mcp-config` JSON file naming
the same release command/args. `--allowedTools` contained only
`mcp__gen_agent_server__instances`, `agents`, `invoke`, and `result`, while
Bash, Edit, and Write were disallowed. The first attempt omitted `--verbose`
and failed locally before a model call because Claude requires it with
`stream-json`. The corrected run used `instances`, `invoke`, and `result`, and
reported `server/default`, `inv-2`, and
`echo: claude-work-machine-smoke`.

## Provider-backed MCP probes

A small `Snodo.Client` script connected to that same packaged stdio entry
point, called `agents`, called `invoke`, and polled `result` once per second
until terminal status. It always closed the client. Its essential control code:

```elixir
{:ok, client} = Snodo.Client.connect(
  {:stdio, release, ["eval", "GenAgentServer.MCP.serve()"]}
)

try do
  {:ok, submitted} = Snodo.Client.call_tool(client, "invoke", %{
    "agent" => provider,
    "prompt" => prompt
  })
  id = get_in(submitted, ["structuredContent", "id"])
  # Poll result(id) to completed/failed/rejected, with a 120-second bound.
after
  Snodo.Client.close(client)
end
```

With `GEN_AGENT_SERVER_PROVIDERS=codex` and `GEN_AGENT_SERVER_CWD` set to the
isolated clone, the exact provider prompt was
`Reply with exactly: gen-agent-provider-ok`; result `inv-2` completed in
4,232 ms with that text and a Codex session ID. With
`GEN_AGENT_SERVER_PROVIDERS=claude`, the exact prompt was
`Reply with exactly: gen-agent-claude-provider-ok`; result `inv-2` completed
in 4,300 ms with that text and a Claude session ID. Both were read-only and
used the server's default provider model selection; the actual backend model
was not reported by these result records. Each MCP client had its own VM and
result store, so the repeated local `inv-2` IDs refer to distinct processes.

No global MCP registration or provider configuration changed. The temporary
clients exited and the Snodo clients closed. This run did not test a shared
long-lived server, cross-client result lookup, restart persistence, or work
machine authentication. Those are separate release-scope decisions.

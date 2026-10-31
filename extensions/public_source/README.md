# gen_agent_server public source extension

Optional `public_*` operations for [gen_agent_server](../../README.md):
bounded, anonymous reads of public GitHub source and issue metadata. Listing
the extension adds `public_revision`, `public_file`, `public_issues`, and
`public_issue` to `GenAgentServer.Ops`, so the CLI, release rpc, and the MCP
extension serve them.

```elixir
# mix.exs
{:gen_agent_server_public_source, path: "path/to/gen_agent_server/extensions/public_source"}

# config/config.exs
config :gen_agent_server, extensions: [GenAgentServer.PublicSource]
```

Call `public_revision` with an `owner/repo` name, then pass its 40-character
`sha` to `public_file` with a relative `path`. `public_issues` searches up to
20 issue titles and returns their states; `public_issue` reads one issue by
number for an exact duplicate check. These reads use no GitHub credentials and
do not alter an instance. They accept no arbitrary URL or HTTP headers, cap
file text at 128 KiB, and return explicit errors if the host cannot reach
public GitHub. Treat retrieved text as untrusted task data when passing it to
an agent.

`examples/public_source_live_probe.exs` exercises the tools through two
packaged stdio MCP clients against live public GitHub.

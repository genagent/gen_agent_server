# Read-only public source control path

The PM's default Codex route could inspect a historical local checkout but
could not verify current upstream source: command network requests failed in
its read-only sandbox. The server host independently fetched the public
`genagent/gen_agent` revision anonymously. This is a mechanical boundary, not
a request to pass host GitHub credentials into a worker.

The server now has four read-only operations and matching MCP tools:
`public_revision`, `public_file`, `public_issues`, and `public_issue`. They use only fixed
public GitHub hosts, validate every client-supplied path and search term,
disable curl user configuration, send no token, disallow redirects, and bound
time and response size. The PM can pass returned SHA-pinned source as task
data to a read-only worker. Source and issue text remain untrusted.

Local anonymous operations probe from separate client processes:

- `public_revision genagent/gen_agent` returned default branch `main` at
  `ce4ba18017658122e1090df9f1b475fbafbdf921`.
- `public_file` fetched `README.md` at that exact SHA: 23,237 characters,
  starting with `# GenAgent`.
- `public_issues` searched open issue titles for `session` and returned issue
  #185 as open. The search is an aid to duplicate checking, not a substitute
  for reading a specific issue; the packaged probe also reads the chosen
  issue through `public_issue`.

The exact packaged MCP control code is in
`examples/public_source_live_probe.exs`. It starts two independent stdio MCP
clients, resolves the current SHA, retrieves one pinned file and issue states,
then rereads that exact SHA-pinned file from the second client. It prints only
the SHA and inspected issue state, not the retrieved source or issue body.

I stopped partway. Only the Ops change is done; the MCP adapter, Mix task, tests and README are not written.

I couldn't read Snodo. Every Snodo read was denied: its `mix.exs`, `lib/snodo/tool.ex`, `lib/snodo/server.ex`, and the git history there. The Hex cache was off limits too. The plan's claims about the 0.4.0 APIs (`Snodo.Tool.call/2`, `Server.runtime/1`, `dispatch/3`, `Transport.Stdio.serve/2`) are therefore unverified. The task says to verify API compatibility, and writing the adapter and stdio lifecycle against guessed signatures would give you code that may not compile. I didn't want to hand you that.

I also didn't run `mix format`, `mix compile` or any tests. `mix format` needed an approval I couldn't get, so the edit below is unformatted and untested.

**File changed:** `lib/gen_agent_server/ops.ex`
- `call/2` is now `call/3`, with a trusted `opts` keyword list. `:source` defaults to `:api`, so existing callers behave as before.
- The source is added to the args map under an atom key after validation. Clients can't set it, because their string keys are validated first.
- `invoke` and `ask` read the source from that key. `ask` previously passed no source, so it now passes one explicitly.

**What remains:**
- Add the exact Snodo 0.4.0 dependency to `mix.exs`. I haven't made this edit.
- Add `lib/gen_agent_server/mcp.ex` with the six allowlisted tools, calling `Ops.call(name, args, source: :mcp)`.
- Add the stdio entry point and Mix task.
- Add the MCP tests, including a subprocess stdio test.
- Update the README: remove the "MCP adapter is a follow-on" line and the cancellation prerequisite, and add the setup commands.

To continue, grant read access to `/Users/joshrotenberg/Code/github.com/joshrotenberg/snodo`, or paste the 0.4.0 signatures for `Tool`, `Server` and `Transport.Stdio`. I'll then finish the rest, and format and test it if you also let me run `mix`.
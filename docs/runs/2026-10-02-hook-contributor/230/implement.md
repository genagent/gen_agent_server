I couldn't run `mix format` or the focused tests because the sandbox blocked every `mix` command. The edit is docs-only, but it hasn't been formatted or tested.

Files changed: `lib/gen_agent.ex`

- **[P2] `checkpoint_session/2` missing from the agent-process row:** fixed. I checked `lib/gen_agent/server.ex` first. The agent runs the callback at line 565 (via line 1505) when a prompt task requests a checkpoint. It also runs it at lines 797 and 805 to restore a checkpoint after a failed or crashed prompt task.
  - I added `checkpoint_session/2` to the `start_session/1` and `terminate_session/1` row.
  - I added a paragraph after the table. A backend's `prompt/3` can call the `:checkpoint` function it receives in its options. The prompt task waits on that synchronous request, and other synchronous agent calls wait while the agent runs the callback. It also notes the restore case.

The rest of the change is unchanged.

The host should run `mix format` and `mix test test/gen_agent/hook_blocking_test.exs`. The new table row is long, so formatting might touch it.
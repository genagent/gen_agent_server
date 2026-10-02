I’ll check the changed guides and tests against the runtime, focusing on error association, admission limits, and ticker shutdown.


The error-handling changes match the runtime’s dispatch order: Watcher separates the active event from newly rejected prompts, and Heartbeat retains its batch. The ticker still has a restart race: it checks the old PID, then sends by name. I’m checking whether the lifecycle test covers that gap.


REQUEST CHANGES

- **[P2] Restart race still allows ticks from the old ticker** — `guides/patterns/heartbeat.md:179–181`: The PID check and name-based notification are separate operations. If the agent stops and its replacement registers between them, the old ticker sends the replacement a tick before processing `:DOWN`. Documenting this race does not satisfy the requested no-duplicate-ticks guarantee. Bind delivery to the monitored incarnation or enforce ticker shutdown before replacement startup. `test/guides/heartbeat_test.exs:160–165` waits for ticker termination before restarting, so it cannot detect this race; add coverage for overlapping shutdown and restart.

The 10 focused tests passed against the checkout’s prebuilt runtime. Changes stay within the requested files; Supervisor drift and cleanup remain deferred to #236.
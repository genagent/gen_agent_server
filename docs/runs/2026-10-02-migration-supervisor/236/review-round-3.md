REQUEST CHANGES

The fix for the synthesis race is correct. The gate it adds introduces a new way for the coordinator to wait forever.

**Blocking**

- `guides/patterns/supervisor.md:217-224`: a rejected synthesis prompt now leaves the coordinator stuck in `:synthesizing`.
  - When the final worker report is buffered during a turn, `drain_pending_events` puts the synthesis prompt on the mailbox through `enqueue_prompt` (`lib/gen_agent/server.ex:1723-1729`).
  - If the mailbox is full (`max_pending_prompts`), `reject_generated_prompt` (`lib/gen_agent/server.ex:1736`) calls `handle_error/3` with `{:overloaded, _}`. `pre_turn/2` never runs, so `synthesis_turn` is still `false`.
  - That error then falls through to the catch-all at line 224, which returns `{:noreply, state}`. Nothing finishes the run and the watcher never receives `:finish`. The code before this round failed the run on any `:synthesizing` error, so this is a regression, and it conflicts with the issue's requirement that the coordinator never wait without a bound.
  - Fix: add a clause before line 224 for `{:overloaded, _}` in `:synthesizing` with `synthesis_turn: false`. It can either call `finish(state, :failed, reason)`, or return `{:prompt, state.synthesis_prompt, state}` so the retry goes through the self-chain slot, which is reserved and dispatched before the mailbox (`server.ex:328`, `server.ex:1752`).
  - Test: start with `max_pending_prompts: 1`, keep one extra tell in flight and one queued, then `notify_ack` the final report and release both turns. Assert the coordinator leaves `:synthesizing`: `:failed` and cleaned up, or done with the synthesis output if you choose the retry.
  - Also mention this case in the guide paragraph at line 462.

**What I checked that holds**

- **The race is real.** Buffered events add their prompts to the end of the mailbox, behind user turns already queued (`server.ex:1696-1729`). `pre_turn/2` runs at dispatch, before the turn starts (`server.ex:1103`). So recognising the synthesis prompt in `pre_turn/2` is the right place.
- **Only the synthesis turn can finish synthesis.** The two new queued-turn tests are deterministic: `notify_ack` is buffered while one turn is in flight and another is queued. Both assert that the final output comes from the synthesis prompt.
- **The guide's extra-turn claims are accurate.** Matching on prompt text is documented as a limitation.
- **The removed `spawn_workers` reference is fixed.** No stale references remain (`supervisor.md:516-517`).
- **The rerun test** now checks that the name is unregistered and restarts every time.
- **The documented 5-second stall** matches the child spec (`shutdown: 5_000`, `server.ex:94`). The chain the guide describes is accurate: the coordinator callback waits on the watcher, which waits on the DynamicSupervisor, which waits for the coordinator to exit.
- **Scope:** the research guide changes and all earlier tests are preserved.
- **Tests:** I ran `mix test test/guides/supervisor_test.exs test/guides/research_test.exs` and all 18 passed. I ran nothing else.
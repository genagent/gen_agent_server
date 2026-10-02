Every claim in #237 and its comment still holds at HEAD `e9920af`. None is resolved yet. I ran no tests. The only runtime check was a standalone `elixir` call to confirm what happens with a name that isn't registered.

## Claims that still hold

**Missing names exit instead of returning `:not_found`**
- `GenAgent.status/2` is a `:gen_statem.call` through the registry (`lib/gen_agent.ex:877-878`). A missing name exits with `{:noproc, ...}`; I confirmed this by running it. So the `_ -> {:error, :not_found}` fallbacks in `inbox`, `summary_get` and `transcript` (`guides/patterns/switchboard.md:206-207`, `:215`, `:231-232`) never run for a missing name.
- `send/2` (`:186`) and `poll/2` (`:194`, `lib/gen_agent.ex:743`) also exit for a missing name.
- A related problem the issue doesn't mention: `notify/2`, `interrupt/1` and `resume/1` are casts (`lib/gen_agent.ex:760`, `:792`, `:857`). A cast to a missing name returns `:ok`, which I also confirmed. So `summary_update/2` and `halt/1` succeed silently when the session doesn't exist.

**`send/2` problems**
- **Name clash:** it is named `send/2` and clashes with the auto-imported `Kernel.send/2` (`:184-185`).
- **Doc is incomplete:** the doc lists two return values. The code also returns `{:error, :halted}` (`:188`), and `tell/2` can return `{:error, {:overloaded, info}}` (`lib/gen_agent.ex:621-631`).
- **Race:** it calls `status` and then `tell` separately, so the busy check can be stale by the time the tell lands. The server already queues a tell when busy or halted (`lib/gen_agent/server.ex:389-395`).
- **Cost:** `status` copies the whole `agent_state`, including the growing history (`lib/gen_agent.ex:858-866`).

**Inbox ack can skip an in-flight result**
- A notify that arrives while a turn is running gets buffered (`server.ex:1025-1031`).
- When the turn finishes, `handle_response/3` updates the state first and the buffered events are applied afterwards (`server.ex:1785-1794`, `1701-1714`).
- The `:ack_inbox` handler then sets the cursor to `length(history)` (`switchboard.md:141-143`). By then the history includes that turn's result, so it is marked read without ever being returned by `inbox/2` (`:200-204`).

**Doc errors**
- `halt/1` is listed as part of `GenAgent`'s public API (`:47-49`), but `GenAgent` has no such function.
- `Keyword.drop(opts, [:name, :backend])` (`:101`) does nothing, because `agent_child_spec` already splits those keys out before `init_agent` runs (`lib/gen_agent.ex:547-555`).
- The Broadcast variation (`:288-291`) says to enumerate the registry. It also tells readers to rely on tell queueing while `send/2` rejects busy sessions.
- The usage example writes a literal `\\n` where a newline is meant (`:280`).

`README.md:441` and `guides/patterns/overview.md` only link to the guide and need no change.

## Smallest change

Full plan: [local Claude plan file path redacted; the findings and plan are summarized above].

**`guides/patterns/switchboard.md`**
1. Rewrite the API list (`:47-49`) to name only the calls the recipe uses, and drop `halt/1`. Say that halting goes through `handle_event` returning `{:halt, state}`.
2. In `init_agent`, return `{:ok, opts, %State{path: path}}` and remove the drop.
3. Change the ack handler to `handle_event({:ack_inbox, seen}, s)`, setting `inbox_cursor: max(s.inbox_cursor, seen)`.
4. Facade changes:
   - **Missing names:** add a private `call/1` that turns an `:exit, {:noproc, _}` into `{:error, :not_found}`, and route every call through it.
   - **`submit/2` replaces `send/2`:** it just calls `GenAgent.tell` with no status check first. Its doc lists `{:ok, ref}`, `{:error, {:overloaded, info}}` and `{:error, :not_found}`, and says busy sessions queue and halted sessions queue until `resume/1`.
   - **`inbox/2`:** take `seen = length(history)` from the same snapshot it reads. On `ack: true`, send it with `notify_ack(name, {:ack_inbox, seen})`, so a result still in flight stays unread.
   - **`summary_get` and `transcript`:** remove the dead fallback clauses. `transcript` returns `{:ok, history}`.
   - **`summary_update` and `halt`:** use `notify_ack` instead of `notify`, so a missing name returns `{:error, :not_found}`.
   - **`interrupt` and `resume`:** document that they are casts and return `:ok` even for a missing name.
5. In the usage example, rename `send` to `submit` and use a real `\n`.
6. Change Broadcast to `broadcast(names, prompt)` over names the application tracks itself. It returns each name's `submit` result, and busy sessions queue.

**New `test/guides/switchboard_test.exs`**

This compiles both modules straight from the guide, the same way `test/guides/pool_test.exs` does. The fixture backend holds a prompt until the test releases it. Tests:
- Each facade function returns `{:error, :not_found}` for a missing name, with no exit.
- **Ack ordering:** one turn completes, and a second turn is held in flight. `inbox(ack: true)` returns only the first. After release, `inbox()` returns only the second.
- Submitting while busy queues, and both turns complete in order.
- With `max_pending_prompts: 1`, a further submit returns `{:error, {:overloaded, _}}`.
- After `halt`, a submit stays pending until `resume`.
- `Switchboard` does not export `send/2`.
- The guide text no longer contains `halt/1` in the API list, a literal `\\n`, or "enumerates the registry".

**Verification:** `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix test`, `mix docs`.

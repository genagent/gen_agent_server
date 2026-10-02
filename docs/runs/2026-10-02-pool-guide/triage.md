I’ll inspect the current guide and core API at the cited areas, then report which findings remain and the smallest scoped fix. I’ll keep the workspace read-only.

I re-checked the current checkout at `df6d873`. **The reported Pool guide findings still hold**; the core API also confirms overload rejection and offers a metadata-only status API that can avoid copying callback state while polling.

### Claims that still hold

- **Overload can crash `Pool.submit/2`.** The guide still matches `{:ok, ref}` from `GenAgent.tell/2` at [pool.md:152–158](/private/tmp/gen_agent_issue_239_pool/guides/patterns/pool.md:152). `tell/2` returns `{:error, {:overloaded, info}}` when pending-queue admission fails ([gen_agent.ex:594–605](/private/tmp/gen_agent_issue_239_pool/lib/gen_agent.ex:594), [gen_agent/server.ex:25–26](/private/tmp/gen_agent_issue_239_pool/lib/gen_agent/server.ex:25)). `Pool.start/2` does not pass pending prompt limits to workers ([pool.md:124–139](/private/tmp/gen_agent_issue_239_pool/guides/patterns/pool.md:124)); the API accepts those options ([gen_agent.ex:496–506](/private/tmp/gen_agent_issue_239_pool/lib/gen_agent.ex:496), [gen_agent.ex:551–581](/private/tmp/gen_agent_issue_239_pool/lib/gen_agent.ex:551)).
- **Failed turns are absent from pool results.** The worker records results only in `handle_response/3` ([pool.md:101–113](/private/tmp/gen_agent_issue_239_pool/guides/patterns/pool.md:101)). `use GenAgent` supplies a default `handle_error/3` that leaves state unchanged ([gen_agent.ex:428–430](/private/tmp/gen_agent_issue_239_pool/lib/gen_agent.ex:428)). `Pool.results/1` reads only that results list ([pool.md:179–183](/private/tmp/gen_agent_issue_239_pool/guides/patterns/pool.md:179)). Accepted turns can still be polled by ref, but the pool does not retain failure/task identity.
- **The round-robin claim is inaccurate under concurrency.** The guide calls it atomic ([pool.md:60](/private/tmp/gen_agent_issue_239_pool/guides/patterns/pool.md:60)), but reads and increments separately ([pool.md:152–155](/private/tmp/gen_agent_issue_239_pool/guides/patterns/pool.md:152)). Concurrent callers can read the same index.
- **Polling copies results unnecessarily.** `wait_for_all/2` polls `GenAgent.status/1` ([pool.md:190–197](/private/tmp/gen_agent_issue_239_pool/guides/patterns/pool.md:190)); that status includes the full `agent_state` ([gen_agent/server.ex:577–591](/private/tmp/gen_agent_issue_239_pool/lib/gen_agent/server.ex:577)). `runtime_snapshot/1` is available and returns bounded metadata without callback state ([gen_agent.ex:898–919](/private/tmp/gen_agent_issue_239_pool/lib/gen_agent.ex:898), [gen_agent/server.ex:594–619](/private/tmp/gen_agent_issue_239_pool/lib/gen_agent/server.ex:594)).
- **Variation text has two defects.** Work-stealing names `next_idx`, while the implementation uses `idx` ([pool.md:241](/private/tmp/gen_agent_issue_239_pool/guides/patterns/pool.md:241), [pool.md:153](/private/tmp/gen_agent_issue_239_pool/guides/patterns/pool.md:153)). Auto-scaling says to “halt” extras ([pool.md:250–253](/private/tmp/gen_agent_issue_239_pool/guides/patterns/pool.md:250)); the guide’s `Pool.stop/1` calls `GenAgent.stop/1`, which terminates the process ([pool.md:186–188](/private/tmp/gen_agent_issue_239_pool/guides/patterns/pool.md:186), [gen_agent.ex:921–934](/private/tmp/gen_agent_issue_239_pool/lib/gen_agent.ex:921)).

### Already resolved

No listed finding appears resolved in this checkout. Core already provides configurable pending limits, overload errors, and `runtime_snapshot/1`; the guide has not adopted them. The guide does **not** explicitly call the mailbox “unbounded,” so that wording need not be corrected; its “backpressure for free” and fire-and-forget claims at [pool.md:46–59](/private/tmp/gen_agent_issue_239_pool/guides/patterns/pool.md:46) still need qualification.

### Smallest scoped change

Edit only [guides/patterns/pool.md](/private/tmp/gen_agent_issue_239_pool/guides/patterns/pool.md):

- Qualify mailbox queueing as bounded, show pending-limit options passed through `Pool.start/2`, and handle the `tell/2` overload return without raising. Have `submit_many/2` preserve each task’s success or rejection.
- Include task identity in worker state and record failures in `handle_error/3` alongside successes.
- Make round-robin selection atomic with a single atomic fetch-and-increment operation, or change the text to describe the weaker actual guarantee.
- Use `runtime_snapshot/1` in `wait_for_all/2`; explain that it checks processing and pending prompts without copying worker results.
- Correct `next_idx` to `idx`, and change scaling guidance to stop extra workers.

The checkout is read-only as requested; no files were changed.
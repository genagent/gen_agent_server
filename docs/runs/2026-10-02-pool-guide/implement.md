I’ll re-check the guide and core API, update the copyable example, and add focused tests for overloads, failed turns, and concurrent dispatch. I’ll keep the changes local and scoped to the guide and its test.


The findings still hold. I’ll use `:atomics.add_get/3` for worker selection, return admission errors to callers, record each turn’s prompt and ref on success or failure, and poll `runtime_snapshot/1`. The test will compile the guide’s code blocks so it exercises the actual example.


The guide edits and six focused tests are in place. The tests cover both queue limits, failed-turn identity, concurrent distribution, metadata-only polling, and stopping extra workers. I’m checking them against the local core using cached dependencies, with no network commands.


- [guides/patterns/pool.md](/private/tmp/gen_agent_issue_239_pool/guides/patterns/pool.md): Fixed overload handling, configurable limits, failure identity, atomic dispatch, metadata polling, and scaling shutdown guidance.
- [test/guides/pool_test.exs](/private/tmp/gen_agent_issue_239_pool/test/guides/pool_test.exs): Added six executable tests against the guide’s code; all passed offline.
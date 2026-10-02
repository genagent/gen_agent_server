I’ll keep this review read-only and check the public API, registration lifecycle, and existing tests against the requested scope.


At checkout `abb0338`, the scoped issue remains **unresolved**. No files were edited.

Claims that still hold:

- There is no public `GenAgent.list/0`; name lookup is provided by [`whereis/1`](</private/tmp/gen_agent_issue_256_20261002/lib/gen_agent.ex:979>).
- Registration carries the name without application metadata: [`agent_child_spec/3`](</private/tmp/gen_agent_issue_256_20261002/lib/gen_agent.ex:604>) supplies `register: via(name)`, and [`via/1`](</private/tmp/gen_agent_issue_256_20261002/lib/gen_agent.ex:986>) uses the existing Registry.
- [`status/2`](</private/tmp/gen_agent_issue_256_20261002/lib/gen_agent/server.ex:577>) and [`runtime_snapshot/2`](</private/tmp/gen_agent_issue_256_20261002/lib/gen_agent/server.ex:594>) still omit dedicated callback-module, backend, agent-start-time, tags, and owning-supervisor fields. Module and backend exist internally; exposing them remains outside this task.
- No `GenAgent.list/0` tests exist. Existing lifecycle tests cover registration and stopping through `whereis/1` ([integration_test.exs:119](</private/tmp/gen_agent_issue_256_20261002/test/gen_agent/integration_test.exs:119>)), which does not satisfy enumeration coverage.

Already supported, with one clarification:

- Unregistered server processes already work through [`Server.start_link/1`](</private/tmp/gen_agent_issue_256_20261002/lib/gen_agent/server.ex:99>) when `:register` is omitted. They still require an internal `:name` option ([server.ex:132](</private/tmp/gen_agent_issue_256_20261002/lib/gen_agent/server.ex:132>)). The “unnamed” test should exercise this existing path, without changing public startup semantics.
- None of the requested enumeration acceptance cases is already resolved. The claim about four sibling applications cannot be verified from this checkout.

Smallest concrete change:

1. **`lib/gen_agent.ex`**: Add `list/0` beside `whereis/1`, with `@spec list() :: [name()]`. Select registered names using `Registry.select(GenAgent.Registry, [{{:"$1", :_, :_}, [], [:"$1"]}])`. Document an unordered, point-in-time registry view, excluding unregistered agents, with no guarantee that returned agents remain alive. Registry cleanup can lag termination, as the existing [whereis regression test](</private/tmp/gen_agent_issue_256_20261002/test/gen_agent/whereis_test.exs:32>) demonstrates.
2. **New `test/gen_agent/list_test.exs`**: Using unique names and the existing mock backend, prove registered agents appear, an unregistered server’s internal name does not appear, and stopped agents eventually disappear. Use membership assertions rather than exact global-list equality; bound the wait for registry cleanup and clean up all created processes.

No metadata, registration changes, Ensemble edits, or pattern-guide edits are needed. Tests were not run during this read-only review.
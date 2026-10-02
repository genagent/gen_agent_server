I’ll verify the API and test conventions, then add `GenAgent.list/0` and focused lifecycle tests within the requested scope.


The plan matches the current code: registration uses the existing Registry, and servers can run without registration. I’ll document the snapshot and cleanup behavior, and use unique names with membership assertions so concurrent tests won’t interfere.


The implementation and tests are in place, and formatting passes. This checkout has no dependencies installed; I found a local cache with a matching lockfile and am using a temporary copy for offline validation. Mix’s TCP-based build lock hit a sandbox restriction, so I’ll disable that lock for the isolated build.


All 28 focused tests passed. The broader suite passed 322 of 324 tests; the two failures involve subprocess fixtures inheriting the temporary dependency/build paths. Formatting and diff checks pass, and only the two requested files are changed.


- [lib/gen_agent.ex](/private/tmp/gen_agent_issue_256_20261002/lib/gen_agent.ex): Added `list/0` with return type and snapshot semantics documented.
- [test/gen_agent/list_test.exs](/private/tmp/gen_agent_issue_256_20261002/test/gen_agent/list_test.exs): Added concurrency-safe tests for registered, unregistered, and stopped agents.

Validation: 28 focused tests passed; full suite 322/324 passed, with two subprocess environment failures. Formatting passed.
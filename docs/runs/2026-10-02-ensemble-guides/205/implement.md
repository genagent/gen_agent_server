I’ll recheck the Strategy docs, server semantics, and the focused test suite first. Then I’ll make the narrow documentation and behavioral test changes within the requested scope.

Changed:

- [strategy.ex](/private/tmp/gen_agent_issue_205_20261002b/extensions/ensemble/lib/gen_agent_ensemble/strategy.ex): documented callback behavior, optional callback fallbacks, synchronous Server execution, `init/1` errors, status map overrides, and token correlation.
- [server_test.exs](/private/tmp/gen_agent_issue_205_20261002b/extensions/ensemble/test/gen_agent_ensemble/server_test.exs): added coverage for `init/1` returning an error and strategy status overriding a base key.

Could not run the focused tests because required Mix dependencies are missing.
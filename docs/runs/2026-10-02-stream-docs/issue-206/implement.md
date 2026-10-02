I’ll re-check the package-shipped references first, then make the smallest documentation and regression-test changes. I’ll leave the test-only Mock modules untouched and won’t run package checks, as requested.

The moduledoc and runtime comment now point to Echo. I added a focused regression test that checks both shipped references and confirms the example’s Echo and Simple modules load. I’m reviewing the diff and all package-shipped references now.

- [gen_agent_ensemble.ex](/private/tmp/gen_agent_issue_206/extensions/ensemble/lib/gen_agent_ensemble.ex): Replaced the moduledoc’s test-only Mock and undefined `MyAgent` with the shipped Simple agent and Echo backend.
- [runtime.exs](/private/tmp/gen_agent_issue_206/extensions/ensemble/config/runtime.exs): Updated the local-use backend example to Echo.
- [shipped_backend_references_test.exs](/private/tmp/gen_agent_issue_206/extensions/ensemble/test/gen_agent_ensemble/shipped_backend_references_test.exs): Added regression coverage for the docs and config references and for the example modules being loadable.

Re-checked package-shipped references; no `GenAgent.Backends.Mock` references remain there. `git diff --check` passed. I did not run package checks.
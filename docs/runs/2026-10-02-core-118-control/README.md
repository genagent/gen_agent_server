# Core #118 server-control run

This run used the packaged server v0.2.0 stdio MCP client for `create_instance` and `ask` on each bounded operation. Codex Luna inspected and verified the change; Codex Astra reviewed it with `APPROVE`. Claude's package gates passed (90 passed, 3 excluded) after recompiling the test-only wrapper. The six-file core PR [#375](https://github.com/genagent/gen_agent/pull/375) merged. Claude adapter release PR [#376](https://github.com/genagent/gen_agent/pull/376) merged, and adapter v0.2.4 was verified on Hex. Issue [#118](https://github.com/genagent/gen_agent/issues/118) remains open only for a missing real `error_during_execution` CLI fixture.

The seven `.exs` files in this directory are exact copies of the ad hoc client scripts used for baseline, verification, rebuild, review, commit, acceptance, and the #81 inspection. Each script starts a separate VM, so this evidence does not demonstrate shared state across client connections. The Codex worker sandbox denied `.git/index.lock`; host Git therefore made the commit, push, PR, and merge. `gh` API access was intermittent inside Codex. Mix's TCP lock required `MIX_OS_CONCURRENCY_LOCK=0`, and the test-only wrapper's compiled artifact was stale until recompiled.

| Operation | Observed control path |
| --- | --- |
| Create a named Codex route; inspect the checkout and issue; execute package gates; diagnose/rebuild the cached test artifact; review the diff | The published MCP `create_instance` and `ask` tools worked. The route's Codex CLI performed the bounded repository operations and returned evidence. Each invocation used a new client process and instance. |
| Commit the approved six-file diff | Attempted through MCP `ask`; the Codex worker's filesystem sandbox denied `.git/index.lock`. The isolated checkout was valid, but the server has no narrow host-side Git commit operation. Host Git completed the commit after this failure was surfaced. |
| Fetch/rebase, push, create/merge PRs, inspect CI and release state, verify Hex publication | Direct host Git, GitHub CLI, and Hex CLI. These are not operations on the current nine-tool MCP surface. GitHub API access from the worker was intermittent. |
| Run the control flow itself | Seven temporary Snodo client scripts. They are reproducible evidence, not a supported reusable PM interface. |

This was a useful server-assisted workflow, **not** a fully server-only one.
The smallest missing host control after an approved diff is a repository-scoped
Git commit operation with explicit path and approval constraints, rather than
an arbitrary host shell tool. Shared instance access and reconnect behavior
remain a separate #81 requirement. A reusable client/control API should also
replace the per-run Snodo scripts; it can expose narrow validation and release
steps without granting workers general operator controls.

## Target workflow

The long-term target is for the Fio PM chat to be the only real session. Technical inspection, editing, testing, review, and release work should run through one supported `gen_agent_server` control path, without a new one-off orchestration script for each operation. Fio product work resumes only after that representative path is demonstrated.

Server issue [#81](https://github.com/genagent/gen_agent_server/issues/81) is the highest-value shared-instance usability gap after this core fix; it is not implemented. Dashboard [#75](https://github.com/genagent/gen_agent_server/issues/75) remains optional. Server v0.2.0 has nine MCP tools and a quickstart resource, but stdio state is per client.

I’ll read the current diff and surrounding lifecycle and backend code, focusing on validation, safety defaults, schema compatibility, and the documentation claims. I won’t edit files.


The parser restricts client input to fixed provider and access options, and the adapters forward the selected model and effort on resumed turns. I’m checking the remaining lifecycle and documentation edge cases, including startup profiles and what stopping an instance removes.


APPROVE

No blocking correctness or safety regressions found.

- [P3] [README.md:294](/private/tmp/gen_agent_server_claude_023/README.md:294) says both `instance` and `agent` are set to a route name. `instance` should be the created instance name (`"pm"`), while `agent` should be a route (`"review"`). Following the wording literally produces `instance_not_found`.

The implementation preserves the six existing MCP tools, validates creation before startup, restricts backend options, forwards model/effort selections, and protects the default instance. The version bump does not claim a published release.

Review was read-only; I did not rerun tests or live provider probes.
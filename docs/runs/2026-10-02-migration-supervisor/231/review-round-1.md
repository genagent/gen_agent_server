I’ll check the added recipes against the package definitions and installed Mix behavior, then review scope and verification coverage.

Installed Mix confirms that both `:sparse` and `:subdir` are supported and place the project at the stated nested path. The sparse explanation is inaccurate: `../..` points to the checkout root, which exists; the missing core files cause the failure. I’m checking the dependency-loading behavior and available verification coverage.

REQUEST CHANGES

- **MIGRATION.md:173–185:** The sparse failure explanation is incorrect. Installed Mix 1.20.4 places the project at `deps/gen_agent_claude/integrations/claude`, so `../..` exists: it is the checkout root. That root lacks the core project files under this sparse selection. Describe the missing core project rather than a nonexistent directory; retain the `GEN_AGENT_HEX=1` requirement.

- **MIGRATION.md:163:** The requested behavioral coverage is missing. Add a focused offline test exercising sparse consumption with and without `GEN_AGENT_HEX`, full-checkout `subdir`, and local-path resolution. A local Git fixture with controlled dependencies can verify these behaviors without fetching `claude_wrapper`; checking prose alone would not suffice.

Scope is correct: only `MIGRATION.md` changed. I confirmed both Git options through installed Mix documentation and inspected Mix’s checkout implementation. Evaluating the actual Claude project confirms the environment switch and local core path. Full dependency fetching was not tested in this read-only environment.
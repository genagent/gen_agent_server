Found by the 2026-10-01 review at `b8f8ab4` and re-verified against `main` at `1a03608` by a read-only Codex worker in a `gen_agent_server` verification pool (genagent/gen_agent_server#25). One verifier per finding: treat file and line references as the starting point for the fix, and re-check them.

## Problem

MIGRATION.md covers where the source moved and says to set GEN_AGENT_HEX=1 for a publishable archive. It does not say how a consumer that used a git or path dependency on one of the old repositories should depend on the new location. A sparse git dependency on a sibling package resolves gen_agent to the path `../..` and fails to compile unless the consumer exports GEN_AGENT_HEX=1.

**Verification on current main.** MIGRATION.md lists the new package directories and explains local path resolution and `GEN_AGENT_HEX=1` for publishing, but gives no consumer git or path dependency recipe (MIGRATION.md:7, MIGRATION.md:22). A sibling package defaults its `gen_agent` dependency to `path: "../.."`; setting `GEN_AGENT_HEX=1` switches it to Hex (integrations/claude/mix.exs:54). In a sparse checkout containing only that sibling package, the default relative path cannot reach the core project, so dependency resolution fails.

## Acceptance

- Tests cover each case above.

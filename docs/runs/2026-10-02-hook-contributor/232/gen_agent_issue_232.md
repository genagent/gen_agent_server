Found by the 2026-10-01 review at `b8f8ab4` and re-verified against `main` at `1a03608` by a read-only Codex worker in a `gen_agent_server` verification pool (genagent/gen_agent_server#25). One verifier per finding: treat file and line references as the starting point for the fix, and re-check them.

## Problem

There is no CONTRIBUTING.md. The README Testing section lists four mix commands that cover only the root package. scripts/quality.sh, which runs the full check set across all six packages, is not mentioned in README.md, RELEASING.md, MIGRATION.md or any workflow. The minimum Elixir version (`~> 1.19`) and the conventional-commit requirement that drives release-please are also not stated for contributors.

**Verification on current main.** There is no `CONTRIBUTING.md` in the repository. The README’s Testing section lists four root-level Mix commands (README.md:486–493). `scripts/quality.sh` runs checks in the root and five subpackages (scripts/quality.sh:4–21), but a repository-wide search found no reference to that script. The Elixir requirement appears in `mix.exs:11`; RELEASING.md:17–23 describes Release Please without stating a commit-message convention.

## Acceptance

- Tests cover each case above.

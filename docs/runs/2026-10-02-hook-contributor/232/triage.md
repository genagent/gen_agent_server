I’ll inspect the current checkout and line-number the relevant docs, scripts, package manifests, and workflow enforcement to see which issue claims still apply.

The working tree is clean at `e44ab6b`. The six-package script and title workflow are present; I’m checking whether the README has since gained any contribution guidance and how sibling packages resolve dependencies.

The documentation gap remains. One detail needs careful wording: the workflow validates PR titles, not commit messages, so a contributor guide should describe only the enforced title convention and avoid claiming commits are checked.

At `e44ab6b`, the main contributor-documentation claims still hold:

- There is no root `CONTRIBUTING.md`. The README’s [Testing section](README.md:508) lists four Mix commands, and [mix.exs](mix.exs:11) requires Elixir `~> 1.19`.
- [scripts/quality.sh](scripts/quality.sh:5) checks the root and five subpackages: `integrations/claude`, `integrations/codex`, `integrations/anthropic`, `integrations/openai`, and `extensions/ensemble`. The README testing section does not mention it.
- The package layout and dependency modes need contributor-facing explanation. Adapter and Ensemble manifests use local path dependencies by default; `GEN_AGENT_HEX=1` switches those dependencies to Hex ([Claude](integrations/claude/mix.exs:55), [Ensemble](extensions/ensemble/mix.exs:44)).
- PR-title enforcement is present: the [workflow](.github/workflows/pr-title.yml:25) invokes a [validator](scripts/check-pr-title.py:11) that accepts Conventional Commit title syntax. It checks PR titles, not commit messages.
- [RELEASING.md](RELEASING.md:17) already documents Release Please and package publishing. It should remain the detailed release manual; a contributor guide can summarize the process and link to it.

Smallest change: add `CONTRIBUTING.md` with source-checkout setup, the Elixir minimum, root quick checks and `scripts/quality.sh`, the six package directories and local-versus-Hex dependency mode, the enforced PR-title convention, and a short release overview linking to `RELEASING.md`. Add a link to it near the README’s Testing section, optionally noting that the listed commands check only the root package. No files are edited.
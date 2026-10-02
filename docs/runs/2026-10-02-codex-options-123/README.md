# Codex session option fix (#123)

The issue combined a wrapper defect (`--verbose` is not a Codex CLI flag) and an adapter defect (`:ephemeral` prevents a GenAgent session from resuming). The wrapper and adapter used separate clean clones so the concurrent work in the normal checkouts was untouched. The installed `codex-cli 0.157.1` rejected `codex --verbose --version` with exit 2; its help lists `--ephemeral` for both `exec` and `exec resume`, but an ephemeral first turn does not persist the thread for the later process to resume.

[Wrapper PR #107](https://github.com/genagent/codex_wrapper_ex/pull/107) makes `verbose: true` fail before launch, retains `false` compatibility, and corrects the docs. It merged, and wrapper 0.5.5 was published on GitHub and Hex. [Adapter PR #368](https://github.com/genagent/gen_agent/pull/368) rejects both enabled options at session startup, preserves explicit `false` values, and requires wrapper 0.5.5. Its full CI passed, it merged, and adapter 0.4.4 was published on [GitHub](https://github.com/genagent/gen_agent/releases/tag/gen_agent_codex-v0.4.4) and Hex.

The wrapper work used one named `GenAgentServer` Switchboard instance, `handoff/4034`, with `max_in_flight: 1`. The exact [control code](issue_handoff_used.exs), [JSON spec](wrapper/wrapper_config.json), [issue text](wrapper/issue.md), and [caller constraints](wrapper/wrapper_notes.md) reconstruct every stage prompt. The script saved [triage](wrapper/triage.md), [implementation](wrapper/implement.md), [review](wrapper/review.md), [diff](wrapper/diff.patch), per-stage metadata, and [summary](wrapper/summary.json) before stopping the instance in `after`.
Provider session IDs are omitted from the public metadata files; model, usage, timing, stage outcome, and control inputs are retained.

| Stage | Provider / requested model | Actual model | Permissions | Result |
| --- | --- | --- | --- | --- |
| Triage | Codex / CLI default | `gpt-6-astra` | Read-only | Confirmed wrapper call paths and planned validation |
| Implement | Claude / `sonnet` | `claude-sonnet-5-5` | Accept edits in isolated wrapper clone | Changed six wrapper files; could not run Mix inside its tool approval boundary |
| Review | Codex / CLI default | `gpt-6-astra` | Read-only | `APPROVE`; inspected fresh/resume and synchronous argument paths |

The caller independently ran wrapper tests (409 passed, four opt-in integrations excluded), strict Credo, format, docs, and `mix codex.contract` against the installed CLI. The adapter's 82 tests (three live exclusions), strict Credo, format, and docs also passed; its suite was rerun against published wrapper 0.5.5 after the dependency update. The wrapper's PR CI passed before merge. The review verdict was evidence for inspection, not a substitute for tests or release verification.

This run exposed a useful control boundary: a model implementation stage can finish with an approved diff while local tool approval prevents it from executing tests. The host caller must record that stage limitation, run validation independently, and gate the dependent adapter on actual wrapper publication rather than on the wrapper source PR alone. The staged server instance did not commit, push, merge, publish, or operate the adapter; those actions stayed with the caller.

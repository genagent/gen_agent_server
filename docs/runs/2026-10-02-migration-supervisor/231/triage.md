I’ll inspect the current migration guide and Mix dependency configuration, then check Mix’s actual support for the proposed sparse git recipe and report the smallest documentation-only fix.

## Claims that still hold

- The migration guide names the consolidated package directories and says published Hex users keep the same package names ([MIGRATION.md](/private/tmp/gen_agent_issue_231_migration/MIGRATION.md:123)).
- It explains that sibling Mix projects use relative paths and that `GEN_AGENT_HEX=1` selects Hex dependencies for a publishable archive ([MIGRATION.md](/private/tmp/gen_agent_issue_231_migration/MIGRATION.md:142)).
- The Claude package confirms the failure mechanism: by default, its `gen_agent` dependency is `path: "../.."`; setting `GEN_AGENT_HEX=1` changes it to a Hex requirement ([integrations/claude/mix.exs](/private/tmp/gen_agent_issue_231_migration/integrations/claude/mix.exs:55)).

The unresolved gap is that the guide gives no consumer dependency examples. In particular, it does not tell consumers of a sibling package from a sparse Git checkout to set `GEN_AGENT_HEX=1` when the core source is absent at `../..`.

## Already resolved

The guide already covers package locations, unchanged Hex package names, sibling path behavior in a source checkout, and the environment switch used for publishing. These do not need to be repeated or redesigned.

Mix 1.20.4’s local `mix help deps` confirms that both `:sparse` and `:subdir` are supported Git dependency options. `:sparse` checks out one directory; `:subdir` searches within a full checkout. The recipe can use either, with that distinction stated accurately.

## Smallest change

Edit only [MIGRATION.md](/private/tmp/gen_agent_issue_231_migration/MIGRATION.md:142). Add a consumer subsection with copyable Mix examples for:

- **Hex:** `{:gen_agent_claude, "~> 0.2.2"}` (using the appropriate package/version for the consumer’s integration).
- **Sparse Git:** `{:gen_agent_claude, git: "https://github.com/genagent/gen_agent.git", sparse: "integrations/claude"}`. State that consumers of this sibling package must run dependency resolution with `GEN_AGENT_HEX=1`, because its default core path points to unavailable `../..`.
- **Full Git checkout with a package subdirectory:** show `subdir: "integrations/claude"` and the same `GEN_AGENT_HEX=1` requirement.
- **Local path:** show a path to the package directory inside a full source checkout, where the core exists at `../..` and the default path dependency works. Distinguish this source checkout workflow from published Hex dependencies.

No dependency code or release versions need changing. A focused test does not appear necessary: the issue is missing consumer guidance, and a test that only checks prose would not verify the recipe.
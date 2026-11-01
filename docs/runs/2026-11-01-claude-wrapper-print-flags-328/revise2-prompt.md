CI found a problem the host checks missed. The CLI contract job also runs mix claude.contract against Claude Code 2.1.220 (see the matrix in .github/workflows/ci.yml, `claude: ["2.1.220", "2.1.309"]`), and on 2.1.220 it reports:

    emitted --restricted is not documented
    emitted --permission-prompts is not documented
    emitted --system-prompt-snapshot is not documented
    emitted --autocompact is not documented
    emitted --append-subagent-system-prompt-file is not documented

These flags do not exist in 2.1.220. The 2.1.309 job passes, so all of them exist by 2.1.309.

Change lib/mix/tasks/claude.contract.ex so a flag can carry the first CLI version it is checked from, and the task checks it only when the reported version is at or after that version:

- A module attribute mapping each of these five flags to "2.1.309". Also include any other flag this PR added that the 2.1.220 run would report; read the code to decide, and say which you added. Do not tag any flag that existed before this PR.
- Parse the reported version from the `--version` output the task already reads (for example "2.1.220 (Claude Code)").
- On an older version, skip the "not documented" finding for a tagged flag, and skip its hidden-flag probe if it is one. Every untagged flag is checked exactly as today.
- A comment saying the tag is the first version the flag is checked on, not a bisected introduction version.
- Tests in test/mix/tasks/claude_contract_test.exs with the existing fake executables: a tagged flag missing from help on an older reported version is not a finding; on a version at or after its tag it is; an untagged missing flag is still a finding on the older version.
- README "Native CLI compatibility": one sentence saying flags newer than a pinned version are checked from the version they are tagged with.

You cannot run commands; the operator runs the checks and the contract against both 2.1.220 and 2.1.316.

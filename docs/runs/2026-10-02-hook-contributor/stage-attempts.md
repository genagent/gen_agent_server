# Provider stage attempts

Session IDs and actual model IDs were read from each completed handoff
summary before a later `revise` or `review_only` pass overwrote it. All
requested models matched the actual models. Each attempt ended by stopping
its named managed server instance; stage reports are in the issue folders.

| Issue and attempt | Provider and actual model | Session | Outcome |
| --- | --- | --- | --- |
| #230 triage | Codex `gpt-6-luna` | `01a0fc18-d705-7ca0-beaf-529c7f09bb50` | Confirmed hooks block synchronous calls. |
| #230 implement | Claude `claude-sonnet-5-5` | `337aceb7-6742-4fcd-bce6-96c76ee16844` | Callback table and behavioral tests. |
| #230 review 1 | Codex `gpt-6-astra` | `01a0fc1a-3eda-7f40-b8ac-ced076fd0312` | Missing checkpoint callback. |
| #230 revise | Claude `claude-sonnet-5-5` | `4bab4622-9cb1-470f-8594-167a0b1bda17` | Added checkpoint details. |
| #230 review 2 | Codex `gpt-6-astra` | `01a0fc1c-74b2-7770-8179-4b55067cfd39` | Crash restoration claim wrong. |
| #230 review 3 | Codex `gpt-6-astra` | `01a0fc1f-8fce-7150-a325-4f91e4535fd1` | Named call coverage incomplete. |
| #230 final review | Codex `gpt-6-astra` | `01a0fc22-f2e7-7331-be59-34856a851c85` | Approved after caller test expansion. |
| #232 triage | Codex `gpt-6-luna` | `01a0fc18-d9e1-7ad2-a0ac-e533c0296a6b` | Confirmed six-package documentation gaps. |
| #232 implement | Claude `claude-haiku-4-5-20251001` | `71ea4c06-064d-4c96-b03d-7e10b1dfacce` | Contributor guide and README link. |
| #232 review 1 | Codex `gpt-6-luna` | `01a0fc1a-214f-7122-881a-0d2c36b9bd5d` | PR-title versus commit-history distinction. |
| #232 revise | Claude `claude-haiku-4-5-20251001` | `2744824a-26c5-41b5-a1ab-cccfebbc721d` | Clarified release wording. |
| #232 review 2 | Codex `gpt-6-luna` | `01a0fc1c-cbb7-74c1-9726-44ccdb8e9f4b` | Scope does not select packages. |
| #232 final review | Codex `gpt-6-luna` | `01a0fc1f-91b4-7b03-9c7d-51a838c0e9d8` | Approved after caller corrected release and ExDoc links. |

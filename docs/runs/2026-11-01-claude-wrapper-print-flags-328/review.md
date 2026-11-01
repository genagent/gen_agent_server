I’ll read the diff and affected code, check each acceptance item, and report code-backed findings without editing files.

The argv paths cover the requested flags. The Session tests verify the resumed turn’s arguments, but don’t verify the request body sent by the real CLI. I also found that `autocompact` accepts a narrower integer range than the issue specifies; I’m checking that boundary and the Credo configuration.

Acceptance:

| Item | Status | Evidence |
|---|---|---|
| Fields, setters, option routing, emission; enum validation | Met | `lib/claude_wrapper/query.ex:125` fields; `:433` and `:482` onward setters; `:750`, `:776`, `:819` option routing; `:1806`, `:1815` emission; `:1940`, `:1952`, `:1958` enum validation. Autocompact’s narrower API is a separate defect below. |
| Explicit false suggestions; unset omitted | Met | `lib/claude_wrapper/query.ex:1895` emits `"false"`; `:1893` omits unset. |
| Manual/default mapping and version documentation | Met | `lib/claude_wrapper/query.ex:1932`, `:1938`; shared mapping at `lib/claude_wrapper/duplex_session.ex:630`; checked versions named in `README.md:217`. |
| Subagent forwarding documented as stream-json only | Met | `lib/claude_wrapper/query.ex:551`; `lib/claude_wrapper/duplex_session.ex:359`. |
| Session snapshot off sends the turn’s system prompt | Not verifiable end to end | `lib/claude_wrapper/session.ex:258` merges turn options; `:276` adds resume. `test/claude_wrapper/session_selector_test.exs:79` verifies the expected argv, but `:66` explicitly identifies this as a fake-CLI test. |
| Contract passes on 2.1.312, including hidden probes | Not verifiable on that version | Three flags added at `lib/mix/tasks/claude.contract.ex:40`; recognition probe at `:106`. The reported host run used 2.1.316. |
| Out-of-scope flags documented | Met | Complete list at `README.md:219`. |

Defects:

- **`lib/claude_wrapper/query.ex:1967`: autocompact rejects positive integers promised by the issue.** The implementation restricts inputs to 100,000–1,000,000, whereas the requested API is `:auto | pos_integer()`. For example, `autocompact: 200` raises before emission. Fix the type and guard to accept positive integers and emit their decimal representation; let the CLI validate its supported range. Update the range-specific documentation and tests at `test/claude_wrapper/query_test.exs:792`.

- **`lib/claude_wrapper/query.ex:125`: the expanded struct exceeds the repository’s configured Credo limit.** `.credo.exs:10` still sets `max_fields: 56`; the supplied host result reports 64. This leaves a required pre-commit check failing. Raise the configured allowance to accommodate the required fields, with a comment explaining the flat CLI option struct, then rerun strict Credo.

Beyond the requested scope:

- The autocompact range restriction is additional policy and should be removed as described above.
- Rejecting `"--"` in `extra_args` (`lib/claude_wrapper/query.ex:602`) should stay: it preserves the promised placement before the prompt separator.
- Contract inspection helpers (`lib/mix/tasks/claude.contract.ex:43`, `:238`, `:249`) support the new regression tests and should stay.

REQUEST CHANGES

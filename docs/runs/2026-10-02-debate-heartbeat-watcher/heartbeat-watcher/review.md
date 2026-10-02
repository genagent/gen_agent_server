I’ll read the changed guides and tests against the runtime, focusing on error ordering, admission semantics, and ticker lifetime.

The runtime supports the guide’s admission and error-ordering claims: deferred events drain after completion callbacks, and a rejected generated prompt reaches `handle_error/3` before `pre_turn/2`. The ticker also guards the name-lookup race by including the monitored PID in each pulse. I’m checking the remaining wording and running the focused tests without network access.

APPROVE

No actionable findings. Verified admission limits, error ordering, halted ticks, and ticker lifecycle against the runtime.

All 10 focused tests passed using freshly compiled runtime code and the actual guide modules, without network or credentials. `git diff --check` passed.

Scope is limited to the two guides and their tests. Supervisor drift and cleanup remain deferred to #236.
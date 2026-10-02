I’ll read the changed files and the relevant Server paths, then check the tests, documentation claims, and scope.

The limit is checked before worker operations are constructed, and rejection uses the existing queue continuation path. The tests cover the requested cases, including a deterministic queue check. I’ll try the focused tests and formatter check next.

APPROVE

No blocking findings. The limit is enforced before worker operations are constructed; rejection returns the documented error and advances queued work. Scope stays within the three permitted files.

- Minor: `extensions/ensemble/guides/workflows/supervisor.md:92` is missing the `...>` prefix used throughout the IEx example.

Validation: all 16 focused tests passed; formatter and `git diff --check` passed.
# CI

`.github/workflows/release.yml` is the only workflow.

- No `push` trigger exists.
- A `dev` to `main` PR runs one required job named `release-ci` with a 10-minute timeout.
- `release-ci` runs Swift ops tests, context checks, app compilation/unit tests, and unsigned packaging preflight.
- It never runs GUI, installs the app, accesses signing secrets, creates tags, or publishes assets.
- The same PR may run once more only after one diagnosed blocking source correction.

Copilot automatic review is disabled. Codex automatic review is repository-scoped and runs on the explicit release PR. Do not request either reviewer from repository code or comments.

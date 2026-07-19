# LexiRay agent guidance

`AGENTS.md` defines the canonical workflow. Runbooks contain narrow operational detail and must not introduce alternative gates or release paths. `lexiray-ops` is the only repository operations entry point.

- `runbooks/verification.md`: changed-scope mapping and retry rule.
- `runbooks/gui-acceptance.md`: isolated GUI scenarios and immutable evidence.
- `runbooks/installation.md`: rare `/Applications` system-boundary install.
- `runbooks/git-workflow.md`: direct `dev` delivery and release PR.
- `runbooks/ci.md`: the single required release job.
- `runbooks/release.md`: manual GitHub-only publishing.
- `runbooks/data-safety.md`: production-data and TCC boundaries.

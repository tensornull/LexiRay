# Verification

Run the smallest mapped gate from the task worktree:

```bash
swift run lexiray-ops verify changed --base <base-sha>
```

The classifier includes tracked, uncommitted, deleted, renamed, and untracked paths. Unknown paths fail with the exact files that need a mapping. Never respond by running all tests or GUI.

Rules:

- Documentation, version, changelog, workflow, signing, and release metadata: ops/static checks only.
- Models, stores, services, and support logic: build plus mapped unit tests.
- Ordinary visible UI: build, mapped unit tests, and named GUI scenarios.
- Shared window/panel code or GUI runner: one full GUI run after scenario-level debugging is stable.
- System boundaries: install and record only the affected installed-app scenario.

Failed GUI or installed acceptance writes immutable evidence. Retry only with the failure ID and a concrete cause; one retry is accepted. A source change creates a new immutable record but does not remove the requirement to link the prior failure.

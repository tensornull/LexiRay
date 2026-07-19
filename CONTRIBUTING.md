# Contributing to LexiRay

LexiRay is a clean-room macOS app. Do not copy source, assets, Objective-C, private behavior, or implementation details from EasyDict or other projects.

## Development

Requirements are macOS 15 or newer, Xcode, Swift, and XcodeGen. Create a Git linked worktree from current `dev` and keep the primary checkout for synchronization and release work.

Implement the smallest complete change and run:

```bash
swift run lexiray-ops verify changed --base <base-sha>
```

The verifier chooses checks from changed paths. Unknown paths must receive an explicit mapping; never substitute a full suite. Debug UI with named scenarios and reserve a full GUI run for shared window/panel code, runner changes, or an explicit request.

With explicit delivery authorization, make one atomic commit and push directly to `dev`. A `dev` push has no remote CI and no task pull request. Remove and prune the linked worktree when finished.

## Reviews and releases

Formal automated review occurs only on an explicit `dev` to `main` release pull request. The required `release-ci` job runs build, unit, operations, and packaging preflight checks without GUI or secrets. Only unresolved Codex P0/P1 findings block alongside that check.

Release PRs use merge commits. After merge, synchronize `dev` to `main`, then manually dispatch the single `Release` workflow with the version and exact SHA. Never create a new tag or publish assets locally; the workflow verifies the signed DMG before creating the tag and public release.

## Safety

- Preserve unrelated dirty work and real user data.
- GUI and installed acceptance use isolated fixtures and UserDefaults.
- Never reset TCC, read real provider credentials, or capture unrelated windows.
- Never commit generated projects, build products, evidence, DMGs, archives, or secrets.

By participating, you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).

# Contributing to LexiRay

Thanks for helping improve LexiRay. Keep changes focused, Swift-only, and aligned
with the clean-room goal.

## Development Rules

- Create `feat/<task>`, `fix/<task>`, `chore/<task>`, or `docs/<task>` from the
  latest `dev`. Only emergency hotfixes branch from `main`.
- Keep changes surgical. Do not include unrelated refactors or formatting churn.
- Use SwiftUI for app surfaces and narrow AppKit bridges for macOS-specific
  edges.
- Do not copy EasyDict source code, assets, UI implementation, Objective-C, or
  private reverse-engineered behavior.
- Do not commit local `.codex/`, build products, DerivedData, xcresults, or
  generated `LexiRay.xcodeproj`.

## Required Checks

Start each change with preflight, then run the changed-scope gate while
iterating:

```bash
./script/preflight.sh change
./script/verify.sh changed
```

Before opening a PR, create and inspect candidate evidence, then run the PR
gate. For app-binary changes, the candidate flow also requires canonical
installation and installed-app Computer Use acceptance; docs/tests-only changes
stop without installation:

```bash
./script/verify.sh candidate
./script/install_applications.sh
./script/verify.sh pr
```

## Pull Requests

- Task PRs target `dev` and use squash merge.
- Release PRs alone target `main` from `dev` and use a merge commit. Sync
  `main` back to `dev` immediately after release.
- Include a concise summary and the exact checks you ran.
- After local CI passes and the PR is open, request the manual dual-agent review:

```bash
./script/request_ai_review.sh <PR_NUMBER>
```

- Address actionable GitHub Copilot and Codex findings before merge. If a fix
  changes code or release behavior, rerun the relevant local gate before asking
  for another review.
- If a GitHub Actions check fails, inspect the failed logs before changing code:

```bash
gh run view <run-id> --log-failed
```

Swift CodeQL failures usually include the manual build step. Treat those as build
failures first, then rerun CodeQL only after the build cause is understood.

## Releases

Release candidates must already have current installed-app Computer Use
evidence. From the tagged `main` checkout, use the resumable orchestrator:

```bash
./script/release.sh doctor <version>
./script/release.sh publish <version>
./script/release.sh status <version>
```

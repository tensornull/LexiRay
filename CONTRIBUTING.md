# Contributing to LexiRay

Thanks for helping improve LexiRay. Keep changes focused, Swift-only, and aligned
with the clean-room goal.

## Development Rules

- Work from `dev`; do not change `main` directly.
- Keep changes surgical. Do not include unrelated refactors or formatting churn.
- Use SwiftUI for app surfaces and narrow AppKit bridges for macOS-specific
  edges.
- Do not copy EasyDict source code, assets, UI implementation, Objective-C, or
  private reverse-engineered behavior.
- Do not commit local `.codex/`, build products, DerivedData, xcresults, or
  generated `LexiRay.xcodeproj`.

## Required Checks

Run the local CI gate before opening a PR:

```bash
./script/ci_local.sh
```

For visible UI, floating-panel, hotkey, OCR, permission, or streaming behavior,
also verify the real workspace-built app:

```bash
./script/build_and_run.sh --verify
```

## Pull Requests

- Target `main` from `dev`.
- Include a concise summary and the exact checks you ran.
- If a GitHub Actions check fails, inspect the failed logs before changing code:

```bash
gh run view <run-id> --log-failed
```

Swift CodeQL failures usually include the manual build step. Treat those as build
failures first, then rerun CodeQL only after the build cause is understood.

## Releases

Release candidates must pass:

```bash
./script/ci_local.sh
./script/release_check.sh <version>
```

After the PR is merged and `main` checks pass, create and push `v<version>`.

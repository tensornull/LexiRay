# LexiRay Agent Contract

## Authority and boundaries

- This file is the canonical repository contract. Detailed, non-duplicated guidance lives in `.agents/runbooks/`.
- Inspect the worktree, current branch, relevant source, tests, and history before changing anything. Preserve unrelated user-owned changes.
- LexiRay is a clean-room macOS selection translation app. Product code stays Swift-only; use SwiftUI with narrow AppKit bridges.
- Regenerate with XcodeGen and never commit `LexiRay.xcodeproj`, build products, evidence, archives, DMGs, or credentials.

## Daily delivery

- Use exactly one Git-registered temporary linked worktree based on current `origin/dev`. Only one task may write to `dev` at a time.
- Make the smallest complete change. Do not create task pull requests to `dev`.
- Run `swift run lexiray-ops verify changed --base <sha>`. The tool owns the path-to-verification mapping and must fail on unknown paths; never replace that failure with broader tests.
- After explicit delivery authorization, create one atomic commit, fast-forward push it directly to `dev`, then remove the worktree and run `git worktree prune`.
- A `dev` push must trigger no GitHub Actions workflow and no automated code review.

## Verification discipline

- Full suites are final gates, never debuggers. Reproduce and iterate with the smallest unit test or named GUI scenario.
- Ordinary visible changes run only mapped scenarios. Full GUI is allowed only for shared window/panel infrastructure, the GUI runner, or an explicit user request.
- Version, changelog, documentation, workflow, signing metadata, and release configuration never trigger GUI verification.
- Installation and Computer Use are limited to TCC, Login Item, global hotkey, selection/OCR/speech, signing/install/lifecycle boundaries, or an explicit user request.
- GUI, installation, and Computer Use produce one immutable, source-fingerprinted JSON record. Never maintain resumable receipts, phase state, saved PIDs, or mutable evidence.
- A failed run must be diagnosed before retry. Supply the prior evidence ID and root cause; the same failure may be retried once.
- Report exact evidence achieved, skipped or blocked checks, artifact paths, and residual risk. Do not claim evidence that was not produced.

## Acceptance data safety

- Automated GUI and installed-app acceptance use an isolated data root, isolated UserDefaults suite, deterministic fixtures, and mock providers.
- Never read, seed, replace, back up, restore, or write real `~/.lexiray`, the production defaults domain, real provider keys/history, or the general pasteboard.
- Use PID-owned window capture and never persist unrelated desktop pixels. Do not reset TCC in the normal loop.
- Never inspect or unlock stale release keychains. Release secrets exist only in the restricted GitHub runner job.

## Review and GitHub policy

- Formal Codex review runs only when an explicit release opens the `dev` to `main` pull request. GitHub review text is English.
- Review only P0/P1 correctness: data loss, security/credentials, signing/TCC identity, packaging, concurrency, permissions, hotkeys/panels, provider ordering, persistence, and clean-room violations.
- Besides the required `release-ci` check, only unresolved Codex P0/P1 findings block a release. Do not expand P2/P3 into the release task.
- Never request Copilot review or post manual `@codex review` comments.

## Release

- `main` changes only through a `dev` to `main` pull request and merge commit. No emergency bypass exists.
- The pull request runs one required `release-ci` job. One diagnosed blocking fix and one additional run are allowed; a second failure closes the release attempt.
- Merge `main` back to `dev` immediately after release merge. Neither branch push starts CI or publishing.
- Publishing requires an explicit manual dispatch with version and exact SHA. GitHub Actions builds, signs, verifies, then creates the tag and public Release.
- Never publish locally, pre-create a new release tag, poll a remote build, or implement fallback/recovery state machines.
- Use the fixed self-signed, non-notarized identity already stored in GitHub secrets. Never generate or replace release signing material.

See `.agents/runbooks/verification.md`, `gui-acceptance.md`, `installation.md`, `git-workflow.md`, `ci.md`, `release.md`, and `data-safety.md`.

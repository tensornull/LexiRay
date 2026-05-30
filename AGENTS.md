# LexiRay Agent Instructions

## Product Goal

LexiRay is a clean-room macOS selection translation app. The user wants the most pleasant macOS translation workflow, with lower UI weight and better UX than older selection-translation tools.

## Non-Negotiables

- Keep the project Swift-only unless the user explicitly approves another language.
- Use SwiftUI for app surfaces and small AppKit bridges for macOS-only edges.
- Do not copy EasyDict source code, assets, UI implementation, or Objective-C.
- Keep changes surgical and minimal.
- Every meaningful change must build or test before handoff.
- Do not commit local `.codex/`, build artifacts, DerivedData, generated Xcode
  projects, xcresults, or release outputs.

## Architecture Defaults

- `App/`: entrypoint and app lifecycle.
- `Views/`: SwiftUI surfaces.
- `Models/`: value models.
- `Stores/`: persisted settings and lightweight app state.
- `Services/`: translation, text selection, hotkeys, panels, speech, permissions.
- `Support/`: helpers, logging, constants.

Use `XcodeGen` to regenerate `LexiRay.xcodeproj`; do not hand-edit the generated project.

## Verification

Build and unit tests are necessary but not sufficient. Do not treat a mock-only
test, a text-box-only script, or a successful compile as UI acceptance.

Preferred local CI loop:

```bash
./script/ci_local.sh
```

`script/ci_local.sh` is the required pre-push and pre-release gate. It performs
the cleanup, `xcodegen generate`, `swiftformat --lint`, and the CI-equivalent
`xcodebuild test` command with `SWIFT_COMPILATION_MODE=wholemodule`. Do not
claim a change is CI-ready until this script passes locally, unless the only
blocker is a clearly documented local machine/toolchain problem.

For visible UI, floating-panel, window, hotkey, OCR, permission, or streaming
behavior changes, final acceptance must be driven through Computer Use against
the real workspace-built `.app`. Capture and inspect multiple screenshots across
the relevant states before handoff. Scripts and unit tests are supporting
evidence only; they do not replace direct Computer-driven UI verification.

Development runs must use the workspace build at `build/DerivedData/Build/Products/Debug/LexiRay.app`.
Every build/run compile must remove stale LexiRay development `.app` bundles first; stale
bundles in Xcode's default `DerivedData/LexiRay-*` can keep old TCC identities alive and
make macOS permissions appear granted while the running app is still untrusted.
`./script/build_and_run.sh` performs this cleanup automatically before building.
Development run builds must also use the stable local signing identity
`LexiRay Local Development`; ad hoc signing changes the TCC code identity on rebuild and
will break Accessibility and Screen Recording again. The run script creates this local
identity when missing and fails the build if the app is still ad hoc signed. If running
any manual `xcodebuild` command for a runnable app, run `./script/clean_dev_apps.sh --apply`
immediately beforehand and pass `CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="LexiRay Local Development" ENABLE_DEBUG_DYLIB=NO`.
Do not launch any non-workspace LexiRay `.app`.
Do not run `tccutil reset` as part of the normal build/run loop. Reset TCC only when the
development signing identity or bundle identity has intentionally changed, then grant the
current canonical workspace app once in System Settings.
Do not copy, overwrite, kill, or otherwise manage `/Applications` or `~/Applications`
release builds during local iteration. Use `./script/clean_dev_apps.sh` to inspect stale
development bundles, and only use `./script/clean_dev_apps.sh --apply` when the listed
paths are under this repo's `build/` directory or Xcode's `DerivedData/LexiRay-*`.

## CI Failure Discipline

- Do not blindly retry GitHub Actions. Inspect the failed run first:
  `gh run view <run-id> --log-failed`.
- Separate workflow/toolchain failures from app regressions before changing
  source. Keep the smallest useful log snippet in the handoff.
- If CodeQL Swift fails during its manual build step, treat it as a build failure
  first; CodeQL analysis cannot be trusted until that build succeeds.
- The May 2026 repeated CI failures were caused by the GitHub `macos-15` runner
  using Xcode 16.4, where Swift 6.1.2 crashed while emitting the LexiRay module.
  The root fix was switching CI, CodeQL, and Release to `macos-26` and selecting
  `/Applications/Xcode.app`. Do not revert that runner/toolchain choice unless a
  fresh GitHub runner inspection proves a better supported replacement.
- The current recurrence-prevention rule is: local `./script/ci_local.sh` first,
  PR checks second, main checks third, release tag last.

## Review Guidelines

Codex review should focus on P0/P1 risks rather than style churn. Prioritize:

- Broken CI, release, signing, packaging, or XcodeGen assumptions.
- SwiftUI state, identity, observation, lifecycle, or main-actor mistakes that
  can make the app show stale data or behave inconsistently.
- Accessibility, Screen Recording, TCC, launch-at-login, hotkey, and app
  identity regressions.
- Translation concurrency, cancellation, provider ordering, copy behavior, and
  settings persistence bugs.
- Clean-room violations, non-Swift code, generated-project edits, committed
  `.codex/`, build artifacts, DerivedData, xcresults, or release outputs.

Do not treat AI review as a substitute for `./script/ci_local.sh`, GitHub
checks, or real UI acceptance when the changed behavior is visible.

## Dual Agent PR Review

- Manual dual review is the default. Do not enable automatic Codex or Copilot
  reviews unless the user explicitly asks.
- After `./script/ci_local.sh` passes and the PR is open, request both AI
  reviews:

```bash
./script/request_ai_review.sh <PR_NUMBER>
```

- The script requests GitHub Copilot with `gh pr edit --add-reviewer copilot`
  and triggers Codex with the exact PR comment `@codex review`.
- If Codex does not react or post a review, confirm Code review is enabled for
  this repository in Codex settings and that the exact `@codex review` trigger
  was posted.
- If Copilot cannot be added as reviewer, confirm the repository and account
  have access to GitHub Copilot Code Review.
- Address actionable AI findings with the same discipline as human review:
  make the smallest fix, rerun the relevant local gate, and request a re-review
  only when needed. Use `./script/request_ai_review.sh <PR_NUMBER> --force-codex`
  to force a new Codex review comment.

## Branch and Release Discipline

- Work on `dev` by default. Do not switch to, commit on, or merge `main` unless
  the user explicitly asks for a main/release operation.
- Public releases use PR flow: prepare on `dev`, open PR to `main`, wait for
  `build-test` and `Analyze Swift`, merge only after checks pass, wait for main
  checks, then push `v<version>`.
- Before tagging a release, run `./script/release_check.sh <version>` from a
  clean worktree.
- Release artifacts are currently unsigned DMGs. README and release notes must
  say that macOS Gatekeeper may warn and users should verify the `.sha256` file.

## Open Source Standards

- Keep `README.md`, `CHANGELOG.md`, release notes, and user-visible behavior in
  sync.
- Record every public release in `CHANGELOG.md` using SemVer and a dated section.
- Keep contributor, support, security, code-of-conduct, issue-template, and PR
  template docs current when process rules change.
- Preserve the MIT license and clean-room rule in user-facing docs.

## UI Direction

- Dense, calm, native macOS.
- No marketing landing page inside the app.
- Prefer system symbols, semantic colors, and materials.
- The floating panel should feel fast, lightweight, and keyboard-friendly.

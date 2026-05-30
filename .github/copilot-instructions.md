# LexiRay Copilot Instructions

LexiRay is a clean-room macOS selection translation app. Keep changes Swift-only
unless the maintainer explicitly approves another language. Use SwiftUI for app
surfaces and narrow AppKit bridges for macOS-specific edges.

Review priorities:

- Flag broken CI, release, signing, packaging, XcodeGen, or generated-project
  assumptions.
- Flag SwiftUI state, identity, observation, lifecycle, or main-actor mistakes
  that can cause stale UI, missed updates, or inconsistent app behavior.
- Flag regressions in Accessibility, Screen Recording, TCC identity,
  launch-at-login, hotkeys, floating panels, translation concurrency,
  provider ordering, cancellation, copy behavior, and settings persistence.
- Flag any clean-room concern: copied GPL source, assets, UI implementation,
  Objective-C, private reverse-engineered behavior, or non-Swift project code.
- Flag committed local `.codex/`, build products, DerivedData, xcresults,
  release outputs, or hand-edited `LexiRay.xcodeproj`.

Required verification standards:

- Meaningful changes must pass `./script/ci_local.sh` before handoff.
- Visible UI, floating-panel, hotkey, OCR, permission, or streaming behavior
  needs real workspace app verification; unit tests and compile success alone
  are not enough.
- Public releases must update README, CHANGELOG, release notes, and version
  metadata consistently, and must mention that current DMGs are unsigned.

Prefer small, surgical fixes. Do not suggest unrelated refactors or style churn.

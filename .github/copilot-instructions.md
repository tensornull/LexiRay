# LexiRay Copilot Review Instructions

Review for concrete P0/P1 user impact, not style churn. LexiRay is a clean-room,
Swift-only macOS selection translation app using SwiftUI plus narrow AppKit
bridges and an XcodeGen-owned project.

Prioritize:

- CI, XcodeGen, signing, TCC identity, installation, packaging, version/tag, or
  release-state errors.
- SwiftUI state/identity/observation/lifecycle and AppKit bridge bugs that cause
  stale UI, lost focus, wrong panel/window behavior, or appearance regressions.
- Main-actor, cancellation, provider ordering, streaming concurrency, copy,
  history, and settings-persistence bugs.
- Accessibility, Screen Recording, hotkey, selection, OCR, speech, launch at
  login, and multi-display regressions.
- Any path that lets automated acceptance read or modify real `~/.lexiray` or
  the normal UserDefaults domain, including failure and SIGKILL.
- Clean-room violations, Objective-C/non-Swift product code, hand-edited
  `LexiRay.xcodeproj`, or committed `.codex`, build, DerivedData, xcresult, DMG,
  or archive output.

Verification expectations:

- PR-ready work runs `./script/verify.sh pr` on the same source fingerprint.
- Visible behavior has scenario, inspected screenshot/contact-sheet, installed
  app, and Computer Use evidence; compilation or mocks alone are insufficient.
- Releases use a fixed self-signed, non-notarized DMG and matching checksum,
  with local packaging preferred and GitHub Release Build as fallback.

State the failure mechanism and smallest correction for each finding. Do not
suggest unrelated refactors or bypass a failing gate.

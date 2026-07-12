---
name: swiftui-pro
description: Review LexiRay's non-trivial SwiftUI and AppKit-bridge changes for macOS API correctness, state and observation, lifecycle, accessibility, maintainability, and runtime risk. Use when the user explicitly requests a SwiftUI review/audit or before handing off a task that materially changes SwiftUI view/state code. Do not use for docs, scripts, copy-only edits, or performance-symptom diagnosis; use swiftui-performance for the latter.
---

# SwiftUI macOS Review

Review for real correctness and user-impacting risk. Follow the repository's
macOS deployment target and conventions; do not apply iOS/UIKit defaults.

## Workflow

1. Read the changed SwiftUI code, its state/model dependencies, and any
   `NSHostingView`, `NSPanel`, window, responder, or event-monitor bridge it
   relies on.
2. Load only the references needed for the review scope.
3. Trace important states and transitions, including key/non-key windows,
   focus, cancellation, appearance, and persistence where relevant.
4. Check that verification covers the real rendered behavior. Compilation and
   unit tests alone do not prove visible macOS behavior.
5. Report only actionable issues with a concrete failure mechanism. Do not
   invent style findings or propose unrelated refactors.

## Review priorities

- State ownership, observation scope, bindings, identity, and view lifetime.
- Main-actor isolation, cancellation, task lifetime, and stale async results.
- AppKit/SwiftUI ownership boundaries, focus/responder behavior, window/panel
  lifecycle, event-monitor cleanup, materials, clipping, and appearance.
- Accessibility names, identifiers, keyboard paths, focus order, Reduce Motion,
  contrast, truncation, and semantic control choice.
- Deprecated APIs, unnecessary type erasure, unstable list identity, expensive
  work in `body`, and broad invalidation.
- Project rules: Swift-only product code, narrow AppKit bridges, XcodeGen, and
  clean-room implementation.

## Output

List findings by severity, then file and exact line. For each, explain the
observable failure, why the current code causes it, and the smallest viable fix.
Include a short code example only when it materially clarifies the fix. If no
actionable issue exists, say so and name any unverified UI state or residual
risk.

## References

- API modernization: [references/api.md](references/api.md)
- Views, identity, and animation: [references/views.md](references/views.md)
- State and observation: [references/data.md](references/data.md)
- Swift and concurrency: [references/swift.md](references/swift.md)
- Accessibility: [references/accessibility.md](references/accessibility.md)
- Native design: [references/design.md](references/design.md)
- Navigation and presentation: [references/navigation.md](references/navigation.md)
- Performance: [references/performance.md](references/performance.md)
- Hygiene: [references/hygiene.md](references/hygiene.md)

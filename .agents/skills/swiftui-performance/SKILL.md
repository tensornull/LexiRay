---
name: swiftui-performance
description: Diagnose and improve measured SwiftUI runtime performance in LexiRay on macOS, including slow rendering, panel or window jank, high CPU or memory, excessive body updates, layout thrash, identity churn, hangs, and Instruments traces. Use when the user reports a performance symptom, requests profiling, or provides performance evidence. Do not trigger for ordinary SwiftUI implementation or general code review.
---

# SwiftUI Performance on macOS

Start from a reproducible symptom and measured evidence. Do not prescribe a
generic SwiftUI rewrite from code smell alone.

## Workflow

1. Define the exact interaction, app state, build configuration, machine/macOS,
   and metric: latency, frame time, update count, CPU, memory, or hang duration.
2. Establish a baseline with the same Release build and scenario that will be
   used after the change.
3. Inspect the smallest relevant code path and state graph. If code alone does
   not identify the cause, capture Instruments evidence.
4. Form one evidence-backed hypothesis, make the smallest targeted fix, and
   rerun the identical scenario.
5. Report before/after metrics, variance, checks performed, and remaining
   uncertainty. Revert or reconsider a change that does not improve the target
   metric.

## macOS diagnosis order

- Main-thread blocking, synchronous file/JSON/image work, and actor hops.
- Broad Observation dependencies or rapidly published state that reevaluates
  large view trees.
- Unstable `ForEach`/`.id` identity, root conditional replacement, and repeated
  object creation in `body`.
- Layout feedback loops involving geometry, preference keys, panel resizing, or
  AppKit-to-SwiftUI callbacks.
- `NSPanel`/`NSWindow` activation, responder churn, event/notification monitor
  leaks, and repeated hosting-view reconstruction.
- Material, clipping, shadow, blur, or overlay compositing costs, especially in
  the floating panel and multi-display OCR overlay.
- Unbounded history/provider collections, repeated parsing/formatting, image
  decoding, and missing cancellation.

## Instruments

Profile the canonical Release app with the SwiftUI, Time Profiler, Hangs, and
Allocations instruments as needed. Capture only long enough to reproduce the
issue and mark the interaction. Use the SwiftUI cause-and-effect graph and body
update lanes to connect an invalidation to its source; corroborate expensive
work in Time Profiler.

Temporary `Self._printChanges()` logging is acceptable in a Debug-only probe,
but remove it after diagnosis. A Debug trace is directional evidence, not a
Release performance result.

## Remediation rules

- Narrow observation at leaf views and pass stable scalar/value inputs.
- Give collections stable identity; never create `UUID()` during rendering.
- Move expensive computation and I/O out of `body` and off the main actor.
- Break layout feedback loops at the owning boundary; do not mask them with
  arbitrary delays or throttles without measurement.
- Preserve view identity unless state reset is intentional.
- Optimize the AppKit bridge when it owns the cost rather than forcing a
  SwiftUI-only solution.

Run the repository's targeted verification and GUI acceptance after performance
checks. A faster panel that breaks focus, sizing, translucency, or cancellation
is not an improvement.

## References

- Mental model and identity: [references/demystify-swiftui-performance-wwdc23.md](references/demystify-swiftui-performance-wwdc23.md)
- Instruments workflow: [references/optimizing-swiftui-performance-instruments.md](references/optimizing-swiftui-performance-instruments.md)
- Main-run-loop hangs: [references/understanding-hangs-in-your-app.md](references/understanding-hangs-in-your-app.md)
- Diagnosis patterns: [references/understanding-improving-swiftui-performance.md](references/understanding-improving-swiftui-performance.md)
- Source index: [references/wwdc-session-sources.md](references/wwdc-session-sources.md)

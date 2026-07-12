# Swift and Concurrency

- Match the repository's Swift language mode, availability, formatting, and
  actor-isolation settings; verify them instead of assuming the newest defaults.
- Prefer modern value-oriented Foundation/Swift APIs when they improve clarity
  without expanding scope.
- Avoid force unwrap/try on recoverable paths. Surface user-action failures on
  the correct app surface rather than swallowing them in logs.
- Keep UI mutation on `MainActor`. Protect mutable shared state with a clear
  actor/ownership boundary and make cross-boundary values `Sendable` where
  required.
- Use structured tasks and cancellation. Review every unstructured or detached
  task for lifetime, ownership, stale-result, and shutdown behavior.
- Do not ban Dispatch mechanically: AppKit/system callback bridges may require
  it. Prefer Swift concurrency for app-owned async flow and document a necessary
  bridge.
- Avoid arbitrary sleep-based sequencing. Observe the real state transition or
  notification when one exists.
- Keep type extraction proportional. Small private helpers may remain beside
  their owner when that improves locality and does not obscure responsibility.

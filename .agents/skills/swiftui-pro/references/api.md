# Modern macOS SwiftUI APIs

- Verify availability against `project.yml` and the actual macOS deployment
  target before recommending a newer API.
- Prefer `foregroundStyle`, shape clipping, modern `onChange` overloads,
  `scrollIndicators`, `NavigationStack`, and value-driven animation when they
  are available and preserve behavior.
- Prefer `Layout` or targeted geometry observation to broad `GeometryReader`
  use, but keep geometry when it is the clearest correct macOS solution.
- Prefer SwiftUI-native APIs for surfaces; retain AppKit where LexiRay needs
  `NSPanel`, responder/focus control, global events, Accessibility, Screen
  Recording, status items, or other macOS-only integration.
- Avoid UIKit types and toolbar placements. Do not translate an iOS API rule
  mechanically to AppKit.
- Modernization is not a reason to change unrelated behavior or raise the
  deployment target.

# SwiftUI Performance Review

- Treat performance smells as hypotheses. Use `swiftui-performance` for a
  measured diagnosis when symptoms or meaningful risk exist.
- Keep `body` and initializers free of blocking I/O, parsing, image decoding,
  repeated sorting/filtering, or expensive formatter construction.
- Preserve stable identity and avoid unnecessary `AnyView`, root subtree swaps,
  or new observable objects during rendering.
- Narrow rapidly changing streaming/provider state to the smallest consumers.
- Watch for AppKit/SwiftUI layout feedback: panel resize → geometry update →
  state publish → panel resize.
- Cancel stale tasks and avoid event/notification monitor leaks.
- Use lazy containers only when the collection size and item cost justify them;
  do not replace a small macOS stack on principle.
- A performance change must preserve focus, panel sizing, appearance,
  cancellation, and accessibility in GUI acceptance.

# SwiftUI Views

- Keep each view readable and give extracted subviews a real responsibility.
  Do not split every small helper into a separate file by rule.
- Move business logic, persistence, and long async work out of layout code.
- Preserve structural identity across state changes unless resetting the view is
  intentional. Use stable IDs for lists and repeated rich-result blocks.
- Prefer native `Button`, `Menu`, `TextField`/`TextEditor`, and keyboard-command
  paths over gestures that hide semantics.
- Choose `TextField(axis: .vertical)` or `TextEditor` from actual IME,
  placeholder, selection, and scrolling requirements; do not substitute one
  based on an iOS heuristic.
- Scope animation to the value that changes and respect Reduce Motion. Avoid
  delay chains whose correctness depends on wall-clock timing.
- Verify source editor focus, marked/committed IME text, placeholder, clear,
  selection, and responder behavior in the real macOS app.
- Verify panels at default/resized, key/non-key, pinned/unpinned, light/dark,
  and streaming/complete states.

# Native macOS Design

- Prefer native labels, menus, buttons, forms, toolbars, keyboard commands,
  semantic colors, system symbols, and standard window behavior.
- Keep the floating panel dense, calm, lightweight, and readable. Preserve its
  keyboard-first path and avoid marketing or decorative dashboard patterns.
- Use flexible layout where text or localization can vary; verify truncation at
  the actual panel/window minimum and resized states.
- Do not use `UIScreen` or mobile tap-area rules. Use `NSScreen`, AppKit window
  geometry, and macOS control metrics where platform geometry is required.
- Treat materials, clipping, corners, shadows, key-window state, and vibrancy as
  a combined AppKit/SwiftUI composition. Verify light/dark, key/non-key, Reduce
  Transparency, and live translucency.
- Prefer system empty/error states only when they fit the compact panel; native
  does not mean forcing a large iOS-style component into a small macOS surface.
- Centralize a repeated design token only after the repetition is real; do not
  create a design system for one value.

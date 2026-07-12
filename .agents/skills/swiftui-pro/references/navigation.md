# macOS Presentation and Windows

- Use `NavigationStack`/`NavigationSplitView` for in-window navigation where
  appropriate; do not force navigation containers onto independent panels.
- Keep sheet/alert ownership on the surface that initiates the action and use
  item-based presentation when an optional model is the source of truth.
- Trace app activation, key/main window state, focus restoration, close/dismiss,
  pinned panels, reopen behavior, and menu-bar/Dock policy.
- Avoid creating duplicate windows/panels or restoring a dismissed panel as a
  side effect of opening Settings.
- Clean up local/global event monitors and notification observers at the same
  lifecycle boundary that created them.
- Verify presentation by keyboard and pointer in the real app.

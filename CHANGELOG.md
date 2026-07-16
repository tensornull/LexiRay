# Changelog

All notable changes to LexiRay are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.1] - 2026-07-16

### Fixed

- Restored missing login-item registration after reinstall when Start at Login
  was previously enabled, while continuing to respect macOS approval and disable
  decisions.
- Checked Screen Recording permission before opening OCR selection, added clear
  recovery actions, and hardened real two-display OCR result handling.
- Reported global hotkey conflicts independently and kept both the selection
  translation popup and OCR shortcut wired during login startup.
- Cleared the rectangular AppKit frame backing around the floating panel so its
  transparent rounded corners and key-window outline render without stray edges.

## [0.4.0] - 2026-07-08

### Added

- Speak the floating panel's source text: a speaker button in the source
  composer reads the input aloud, choosing a voice from the locally detected
  language. Source and translated-text speech are mutually exclusive.

### Fixed

- Fixed the floating panel opening too short for Chinese (and other CJK) results,
  which clipped content or forced scrolling. Panel height is now driven by the
  view's real measured layout instead of a per-character estimate.
- Fixed the floating panel showing square white corners over its rounded glass
  background while selected (key). The hosting content is now clipped to the
  rounded shape by a container inside the glass view, so the corners stay clean
  in both key and non-key states while the glass keeps its live translucency.

### Changed

- Reworked floating panel sizing to grow from SwiftUI's measured content height,
  removing the hand-tuned layout estimator. The panel keeps its manual
  drag-width and vertical-only growth.
- Focus handling, event-monitor cleanup, resize persistence, and
  keyboard-shortcut routing in the floating panel were hardened for correctness.

## [0.3.2] - 2026-07-04

### Fixed

- Fixed source text editor placeholder behavior with input method (IME) composition. The placeholder now correctly hides when typing begins and shows when the input is empty, matching HapiGo's behavior.
- Fixed inline pinyin preview visibility during Chinese input. Users can now see real-time composition text (e.g., "zuixin zhuangtai") in the input box as they type, instead of only seeing the candidate window.
- Improved IME transaction handling to prevent SwiftUI render cycles from interrupting active input composition.

## [0.3.1] - 2026-07-02

### Fixed

- Fixed code signing consistency issue that caused "invalid signature (-67034)" errors when upgrading from previous versions. All releases now use a unified signing certificate to ensure smooth upgrades.

## [0.3.0] - 2026-07-01

### Added

- HapiGo-style language selector: the floating panel now shows dual source/target
  language pickers with Auto/Once/Always modes. "Auto" detects the source language
  and resolves the target from your pair; "Once" pins a language for the current
  translation only; "Always" saves it as the persistent default. The pickers display
  the resolved language (e.g., "Auto: English") after translation.
- OCR now works on secondary displays: each screen gets its own overlay window for
  region selection, fixing the issue where OCR was only available on the main display.

### Fixed

- The floating panel no longer dismisses when you click its right-edge or bottom-edge
  resize handle. A resize-grab mouseDown now correctly counts as an "inside the panel"
  event instead of triggering the outside-click dismiss.
- The floating panel's rounded corners are now smooth on Retina displays (no more
  jagged edges). The macOS 26+ `NSGlassEffectView` path now trusts the view's own
  anti-aliased corner rendering instead of stacking redundant layer masks.
- ChatCompletions provider (and compatible endpoints) now translate correctly instead
  of treating input as conversational chat. The user message now restates the
  translation instruction around the source text, matching the Anthropic Messages
  provider's behavior.
- Provider rows in the idle panel are no longer cramped: row height increased from
  36pt to 48pt with better vertical spacing, making the layout more breathable and
  matching HapiGo's visual density.

## [0.2.3] - 2026-06-23

### Fixed

- Re-summoning the panel after clearing the input box now opens blank
  instead of restoring the previous translation. Content is retained
  only when the source text is non-empty at dismiss time.
- Disabled ("Off") providers sink to the bottom of the floating panel;
  enabled providers stay on top. Provider order in Settings is unchanged.
- Manually dragging the panel to a narrower width no longer snaps back
  to the default width on the next content change.

## [0.2.2] - 2026-06-23

### Fixed

- Opening the main or Settings window from the menu bar no longer brings a
  dismissed floating panel back on screen alongside the window.
- The floating panel keeps a fixed width and grows only vertically as content
  arrives, instead of also widening with longer text. A manual drag-resize of
  the width is still preserved.

### Added

- The floating panel now restores the previous input text and translation
  results when it is re-summoned without a new text selection within five
  minutes of being dismissed, instead of always opening blank.

### Changed

- CodeQL analysis no longer runs on pull requests (it still runs on pushes to
  `main` and on the weekly schedule), so PRs are not gated on the long
  analysis.

## [0.2.1] - 2026-06-22

### Fixed

- LexiRay no longer takes a Dock slot. It now runs as a menu bar background
  agent (`LSUIElement`) and launches straight into the menu bar without
  auto-opening the main window, so the Dock icon stays hidden even while the
  Settings window is open. The Dock icon only returns as a fallback when the
  menu bar icon is turned off.
- The floating panel keeps a consistent width and baseline height across the
  idle, translating, and translated states. It now opens at one size and only
  grows when the content needs more room, instead of jumping in width and
  height between states.

## [0.2.0] - 2026-06-14

### Added

- Added progressive floating panel growth that resizes as streaming partial
  results arrive, coalescing resizes to keep the motion smooth.
- Added a provider standby preview to the blank floating panel so configured
  providers and setup status are visible before entering source text.
- Added a GUI scenario for preserving a manually resized floating panel through
  the current panel session.

### Changed

- Refreshed the floating panel surface with system glass (on macOS 26, with a
  visual-effect fallback on earlier macOS), a larger corner radius, and
  lighter, top-aligned content.
- Made the source text editor height follow its content between a minimum and
  maximum, and hid the result area for the blank composer so empty states no
  longer show a large card.
- Preserved manual floating panel resize as a current-session lower bound while
  still allowing automatic growth for larger streaming or result content.
- Updated source text color to follow the effective macOS appearance.
- Updated OpenAI and Anthropic provider icons to render in their official
  colors in provider rows and menus.

## [0.1.3] - 2026-06-13

### Changed

- Changed release DMGs to require a fixed self-signed app signature so macOS
  permissions bind to a stable LexiRay identity.
- Added App Identity diagnostics and local signed DMG packaging to prevent
  permission-sensitive workflows from running under unstable app identities.

### Fixed

- Fixed Settings permission rows so Accessibility and Screen Recording status
  refresh while the Settings tab is visible.
- Blocked Selection and OCR when LexiRay is unsigned, ad hoc signed, or running
  beside another LexiRay copy with a different executable path.
- Fixed rich translation results clipping at the floating panel's right edge for
  long inline-code runs and unspaced CJK text.
- Fixed the OCR selection overlay staying blank until the first drag and the
  prompt centering on the multi-display union instead of the active screen, and
  removed drag jank by compositing the overlay with CALayers.

## [0.1.2] - 2026-06-02

### Changed

- Improved translation history browsing feedback in the floating panel with a
  visible history position while moving through saved items.
- Moved translation history limit settings into a dedicated History section.

### Fixed

- Fixed history persistence so in-progress provider batches can become
  browsable as soon as the first provider result finishes.
- Fixed pinned floating panels so Escape closes the panel directly.

## [0.1.1] - 2026-05-30

### Added

- Added Start at Login support through macOS Login Items.
- Added an Auto Copy setting for copying the first provider-ordered successful
  translation result.
- Added local CI and release-check scripts for repeatable pre-release gates.
- Added open-source project documents and GitHub issue/PR templates.

### Changed

- Improved provider translation task coordination and streaming concurrency.
- Improved copy toast routing so main-window and floating-panel copy actions
  display feedback on the correct surface.
- Improved rich translation rendering identity stability for repeated Markdown
  blocks and inline tokens.
- Documented the CI failure root cause and the required prevention workflow in
  the agent instructions.

### Fixed

- Fixed SwiftFormat lint blockers in the 0.1.1 working tree.
- Fixed release-prep hygiene by ignoring local `.codex/` agent assets.

## [0.1.0] - 2026-05-30

### Added

- Initial unsigned public DMG release.
- Added clean-room macOS selection translation with menu bar controls, global
  shortcuts, floating panel translation results, OCR selection, translation
  history, provider settings, copy formats, and local development signing tools.

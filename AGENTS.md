# LexiRay Agent Instructions

## Product Goal

LexiRay is a clean-room macOS selection translation app. The user wants the most pleasant macOS translation workflow, with lower UI weight and better UX than older selection-translation tools.

## Non-Negotiables

- Keep the project Swift-only unless the user explicitly approves another language.
- Use SwiftUI for app surfaces and small AppKit bridges for macOS-only edges.
- Do not copy EasyDict source code, assets, UI implementation, or Objective-C.
- Keep changes surgical and minimal.
- Every meaningful change must build or test before handoff.

## Architecture Defaults

- `App/`: entrypoint and app lifecycle.
- `Views/`: SwiftUI surfaces.
- `Models/`: value models.
- `Stores/`: persisted settings and lightweight app state.
- `Services/`: translation, text selection, hotkeys, panels, speech, permissions.
- `Support/`: helpers, logging, constants.

Use `XcodeGen` to regenerate `LexiRay.xcodeproj`; do not hand-edit the generated project.

## Verification

Preferred local loop:

```bash
./script/build_and_run.sh --verify
```

Preferred test loop:

```bash
xcodegen generate
xcodebuild test -project LexiRay.xcodeproj -scheme LexiRay -configuration Debug CODE_SIGNING_ALLOWED=NO
```

## UI Direction

- Dense, calm, native macOS.
- No marketing landing page inside the app.
- Prefer system symbols, semantic colors, and materials.
- The floating panel should feel fast, lightweight, and keyboard-friendly.


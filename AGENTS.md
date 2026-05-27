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

Development runs must use the workspace build at `build/DerivedData/Build/Products/Debug/LexiRay.app`.
Every build/run compile must remove stale LexiRay development `.app` bundles first; stale
bundles in Xcode's default `DerivedData/LexiRay-*` can keep old TCC identities alive and
make macOS permissions appear granted while the running app is still untrusted.
`./script/build_and_run.sh` performs this cleanup automatically before building.
Development run builds must also use the stable local signing identity
`LexiRay Local Development`; ad hoc signing changes the TCC code identity on rebuild and
will break Accessibility and Screen Recording again. The run script creates this local
identity when missing and fails the build if the app is still ad hoc signed. If running
any manual `xcodebuild` command for a runnable app, run `./script/clean_dev_apps.sh --apply`
immediately beforehand and pass `CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="LexiRay Local Development" ENABLE_DEBUG_DYLIB=NO`.
Do not launch any non-workspace LexiRay `.app`.
Do not run `tccutil reset` as part of the normal build/run loop. Reset TCC only when the
development signing identity or bundle identity has intentionally changed, then grant the
current canonical workspace app once in System Settings.
Do not copy, overwrite, kill, or otherwise manage `/Applications` or `~/Applications`
release builds during local iteration. Use `./script/clean_dev_apps.sh` to inspect stale
development bundles, and only use `./script/clean_dev_apps.sh --apply` when the listed
paths are under this repo's `build/` directory or Xcode's `DerivedData/LexiRay-*`.

Preferred test loop:

```bash
./script/clean_dev_apps.sh --apply
xcodegen generate
xcodebuild test -project LexiRay.xcodeproj -scheme LexiRay -configuration Debug CODE_SIGNING_ALLOWED=NO
./script/clean_dev_apps.sh --apply
```

## UI Direction

- Dense, calm, native macOS.
- No marketing landing page inside the app.
- Prefer system symbols, semantic colors, and materials.
- The floating panel should feel fast, lightweight, and keyboard-friendly.

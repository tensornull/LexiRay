# LexiRay

LexiRay is a clean-room macOS selection translation app built with SwiftUI and narrow AppKit bridges.

The goal is a fast, polished translation surface for selected text:

- Menu bar control and settings window.
- Global shortcuts for translating the current selection and OCR regions.
- Text extraction pipeline: Accessibility, browser AppleScript, then simulated copy.
- Local OCR through ScreenCaptureKit and Vision.
- Floating translation panel near the pointer.
- Provider pipeline with system dictionary, OpenAI Chat Completions, OpenAI Responses, Anthropic Messages, and Gemini GenerateContent. Mock translation is reserved for tests.

## Development

Requirements:

- macOS 15+
- Xcode 16.4+ or newer
- XcodeGen
- SwiftFormat

Install local tools:

```bash
brew install xcodegen swiftformat
```

Generate and build:

```bash
xcodegen generate
./script/build_and_run.sh --verify
```

Run from Codex or terminal:

```bash
./script/build_and_run.sh
```

The run script owns the local development SOP: it removes stale development app bundles,
creates a stable `LexiRay Local Development` signing identity when needed, signs the
workspace debug app with it, disables Debug dylib splitting for local runs, verifies the
result is not ad hoc signed, and launches only:

```text
build/DerivedData/Build/Products/Debug/LexiRay.app
```

Grant Accessibility and Screen & System Audio Recording to that app once in System
Settings. Normal rebuilds should not reset TCC or require reauthorizing permissions.

Run tests:

```bash
./script/clean_dev_apps.sh --apply
xcodebuild test -project LexiRay.xcodeproj -scheme LexiRay -configuration Debug CODE_SIGNING_ALLOWED=NO
./script/clean_dev_apps.sh --apply
```

## Clean-Room Rule

LexiRay may study publicly documented product behavior from existing tools, but must not copy GPL source code, assets, UI implementations, or private reverse-engineered details.

# LexiRay

LexiRay is a clean-room macOS selection translation app built with SwiftUI and narrow AppKit bridges.

The goal is a fast, polished translation surface for selected text:

- Menu bar control and settings window.
- Global shortcut for translating the current selection.
- Text extraction pipeline: Accessibility, browser AppleScript, then simulated copy.
- Floating translation panel near the pointer.
- Provider pipeline with mock, system dictionary, and OpenAI-compatible providers.

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
xcodebuild -project LexiRay.xcodeproj -scheme LexiRay -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Run from Codex or terminal:

```bash
./script/build_and_run.sh
```

Run tests:

```bash
xcodebuild test -project LexiRay.xcodeproj -scheme LexiRay -configuration Debug CODE_SIGNING_ALLOWED=NO
```

## Clean-Room Rule

LexiRay may study publicly documented product behavior from existing tools, but must not copy GPL source code, assets, UI implementations, or private reverse-engineered details.


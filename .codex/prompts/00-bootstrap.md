# Bootstrap LexiRay

You are working in the LexiRay repository. Create or update only the files needed for the requested bootstrap step.

Rules:

- Keep the project clean-room and MIT-compatible.
- Use SwiftUI for app UI, AppKit only for global hotkeys, AX text selection, NSPanel, status/window activation, and system integrations SwiftUI cannot model.
- Use XcodeGen; never hand-edit `LexiRay.xcodeproj`.
- Run `xcodegen generate` and the most relevant `xcodebuild` command before finishing.

Success criteria:

- The app builds on macOS 15+.
- Tests pass.
- Codex Run action points at `./script/build_and_run.sh`.
- CI workflows are present and deterministic.


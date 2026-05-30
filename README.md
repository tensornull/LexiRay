# LexiRay

LexiRay is a clean-room macOS selection translation app built with Swift and
SwiftUI. It is designed to keep translation close to the text you are reading or
writing: select text, trigger a shortcut, and get a lightweight floating panel
near your current work.

## Features

- Menu bar app with a compact settings window.
- Global shortcuts for translating selected text and OCR regions.
- Selection reader fallback chain: Accessibility, browser AppleScript, then
  simulated copy.
- Local OCR through ScreenCaptureKit and Vision.
- Floating translation panel with provider-by-provider results.
- Translation history, retranslation, speech, copy formats, and optional
  auto-copy of the first provider-ordered successful result.
- Provider support for the system dictionary, OpenAI Chat Completions, OpenAI
  Responses, Anthropic Messages, and Gemini GenerateContent. The mock provider is
  reserved for tests.
- Optional "Start at login" using macOS Login Items.

## Install

Download the latest DMG from
[GitHub Releases](https://github.com/tensornull/LexiRay/releases).

Current release builds are unsigned and not notarized. macOS Gatekeeper may warn
when opening the app. Verify the downloaded DMG with the published `.sha256`
file before installing.

LexiRay needs these macOS permissions for its core workflows:

- Accessibility: read selected text and show the floating panel near your work.
- Screen & System Audio Recording: capture only the OCR region you select.
- Automation: read selected browser text when Accessibility cannot provide it.

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

Run the same gate used before pushing or releasing:

```bash
./script/ci_local.sh
```

Run the app from the workspace build:

```bash
./script/build_and_run.sh --verify
```

The run script owns the local development app identity. It removes stale
development bundles, creates or reuses the `LexiRay Local Development` signing
identity, signs the workspace debug app with it, disables Debug dylib splitting,
and launches only:

```text
build/DerivedData/Build/Products/Debug/LexiRay.app
```

Grant Accessibility and Screen & System Audio Recording to that app once in
System Settings. Normal rebuilds should not reset TCC or require reauthorizing
permissions.

## Release

Release preparation for `0.1.1` and later must start from `dev`:

```bash
./script/ci_local.sh
./script/release_check.sh 0.1.1
```

Open a PR from `dev` to `main`. After the PR checks pass and `main` is updated,
wait for `main` CI and CodeQL to pass, then tag the release:

```bash
git tag v0.1.1
git push origin v0.1.1
```

The tag triggers the unsigned DMG release workflow.

## Clean-Room Rule

LexiRay may study publicly documented product behavior from existing tools, but
must not copy GPL source code, assets, UI implementations, Objective-C, or
private reverse-engineered details.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). By participating, you agree to follow
the [Code of Conduct](CODE_OF_CONDUCT.md).

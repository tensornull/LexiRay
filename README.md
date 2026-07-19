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
- Translation history, retranslation, speech for both source and translated
  text, copy formats, and optional auto-copy of the first provider-ordered
  successful result.
- Provider support for the system dictionary, OpenAI Chat Completions, OpenAI
  Responses, Anthropic Messages, and Gemini GenerateContent. The mock provider is
  reserved for tests.
- Optional "Start at login" using macOS Login Items.

## Install

Download the latest DMG from
[GitHub Releases](https://github.com/tensornull/LexiRay/releases).

Current release builds are signed with a fixed self-signed certificate and are
not notarized. macOS Gatekeeper may still warn when opening the app. Verify the
downloaded DMG with the published `.sha256` file before installing.

The fixed release signature gives macOS a stable app identity for Accessibility
and Screen & System Audio Recording. If you installed an older unsigned release,
remove the old LexiRay rows from Privacy & Security, install the current build,
and grant permissions to LexiRay once.

LexiRay also checks its running app identity in Settings. Selection and OCR are
blocked when the app is unsigned, ad hoc signed, or another LexiRay copy with the
same bundle identifier is running, because those states can make macOS bind
permissions to the wrong app.

LexiRay needs these macOS permissions for its core workflows:

- Accessibility: read selected text and show the floating panel near your work.
- Screen & System Audio Recording: capture only the OCR region you select.
- Automation: read selected browser text when Accessibility cannot provide it.

## Development

Requirements:

- macOS 15+
- Xcode 16.4+ or newer
- XcodeGen

Install XcodeGen, create a temporary linked worktree from `dev`, and run the
changed-scope verifier:

```bash
brew install xcodegen
git worktree add ../LexiRay-task dev
swift run lexiray-ops verify changed --base HEAD
```

The verifier maps changed paths to the narrowest build, unit, and GUI checks.
Unknown paths fail instead of expanding to a full suite. Run a named GUI
scenario directly when debugging visible behavior:

```bash
swift run lexiray-ops gui list
swift run lexiray-ops gui run panel_blank
```

Full GUI verification is restricted to shared window/panel infrastructure,
runner changes, or an explicit request. Installation and Computer Use are
restricted to macOS system boundaries. Their evidence is immutable and bound to
the source fingerprint:

```bash
swift run lexiray-ops gui run --all --reason explicit
swift run lexiray-ops install
swift run lexiray-ops accept launch --result passed --screenshot build/acceptance-artifacts/<run-id>/capture.png
```

Daily delivery pushes an atomic commit directly to `dev`. A `dev` push runs no
remote CI and opens no task pull request. Remove and prune the temporary
worktree immediately after delivery.

## Release

An explicit release opens the only pull request path, `dev` to `main`. The PR
runs one required 10-minute `release-ci` job and one automatic Codex P0/P1
review. It never runs GUI or accesses signing secrets.

```bash
swift run lexiray-ops verify release-pr --base <main-sha> --head <dev-sha>
```

After merge, manually dispatch the single `Release` workflow with the exact
version and SHA. Its 20-minute, single-instance job imports the existing P12
only in the runner, builds and verifies the signed DMG, then creates the tag and
public GitHub Release. A failure creates neither. There is no local publish,
fallback builder, polling, or recovery state.

```bash
gh workflow run release.yml -f version=0.4.3 -f sha=<exact-sha>
```

## Clean-Room Rule

LexiRay may study publicly documented product behavior from existing tools, but
must not copy GPL source code, assets, UI implementations, Objective-C, or
private reverse-engineered details.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). By participating, you agree to follow
the [Code of Conduct](CODE_OF_CONDUCT.md).

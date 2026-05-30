# Changelog

All notable changes to LexiRay are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

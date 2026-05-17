# Release Prompt

Prepare a LexiRay release.

Checklist:

- CI is green on `main`.
- Version and build number are updated.
- Archive builds with hardened runtime.
- App is signed with Developer ID Application.
- Notarization succeeds with `notarytool`.
- Stapling succeeds.
- DMG installs and launches on a clean machine.
- `spctl -a -vv LexiRay.app` passes.
- GitHub Release includes DMG, zip, checksums, and release notes.

Do not invent missing secrets. If signing or notarization secrets are absent, stop and report the exact missing secret names.


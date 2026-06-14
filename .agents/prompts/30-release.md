# Release Prompt

Prepare a LexiRay release.

Checklist:

- Start from `dev`.
- Version, build number, and `CHANGELOG.md` are updated.
- `./script/ci_local.sh` passes.
- `./script/release_check.sh <version>` passes from a clean worktree.
- PR checks pass before merging `dev` to `main`.
- `main` CI and CodeQL pass before tagging.
- Tag with `v<version>` only after `main` is green.
- The tag-triggered release workflow produces the fixed self-signed,
  non-notarized DMG.
- GitHub Release includes the DMG and checksum, and the notes mention the
  Gatekeeper warning plus `.sha256` verification.

Do not invent missing secrets. If release signing secrets are absent, stop and
report the exact missing secret names.

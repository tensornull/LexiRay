# Release Prompt

Prepare a LexiRay release.

Checklist:

- Start from `dev`.
- Version, build number, and `CHANGELOG.md` are updated.
- `./script/ci_local.sh` passes.
- `./script/release_check.sh <version>` passes from a clean worktree.
- PR checks pass before merging `dev` to `main`.
- `main` CI and CodeQL pass before tagging.
- If PR/main checks are slow, give the run URLs and resume commands instead of
  long-polling inside the Codex session.
- Tag with `v<version>` only after `main` is green.
- From the exact tagged release checkout, run
  `./script/publish_release.sh <version>` to build, sign, verify, and upload the
  fixed self-signed, non-notarized DMG plus checksum from the local machine.
- GitHub Release includes the DMG and checksum, and the notes mention the
  Gatekeeper warning plus `.sha256` verification.
- The Release workflow only validates published assets and checksum; it must not
  be treated as the artifact builder.

Do not invent missing signing material. If the local release signing identity or
P12 environment is absent, stop and report the exact missing requirement. Remote
repository secrets are fallback only, not the default release path.

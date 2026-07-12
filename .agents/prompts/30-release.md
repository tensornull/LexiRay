# Release LexiRay

An explicit user request to release authorizes the complete workflow without
step-by-step confirmation. Follow `AGENTS.md` and
`.agents/runbooks/release.md`; do not duplicate or improvise the release state
machine here.

Start release preparation with `./script/preflight.sh release`. Require a
current candidate receipt, installed-app Computer Use acceptance, consistent
version/build/CHANGELOG/notes, the documented dev-to-main merge topology, green
local/PR/main gates, and exact tag/source alignment. After the tag is pushed,
run `./script/release.sh doctor <version>` and
`./script/release.sh publish <version>`.

Package locally with the fixed self-signed release identity when it is
available. If it is unavailable, use the existing GitHub Release Build fallback
and resume with `./script/release.sh status <version>`; never generate new
signing material, unlock the obsolete random-password keychain, or read
credentials from another project.

Verify the published DMG and checksum against tag/main, state that it is
self-signed and non-notarized, and sync `main` back to `dev` before starting the
next task. Report each release evidence state and any resumable blocker.

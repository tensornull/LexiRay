# Release Runbook

Use this runbook only after the release PR is merged, `main` checks pass, the
`v<version>` tag is pushed, and the same source fingerprint has a candidate
receipt with installed-app Computer Use acceptance.

## Interface

```bash
./script/release.sh doctor 0.4.1
./script/release.sh publish 0.4.1
./script/release.sh status 0.4.1
```

- `doctor` is noninteractive. It checks the clean tagged checkout, `origin/main`,
  Info.plist, CHANGELOG, current candidate receipt, installed/Computer Use
  evidence, successful CI and CodeQL push runs for the exact SHA, GitHub
  authentication, and the fixed signing identity. It never
  unlocks a keychain or calls a command that can ask for a keychain password.
- `publish` is local-first. When the exact fixed identity is accessible it
  packages, verifies, uploads, downloads, and re-verifies the DMG and SHA-256.
  Otherwise it dispatches the existing `Release Build` workflow. That workflow
  can produce only a private, seven-day build artifact; it cannot create or
  publish a GitHub Release.
- `status` performs one remote inspection. After a successful fallback build,
  it revalidates the local installed-app/Computer Use handoff, downloads and
  verifies the private artifact, then promotes it through the draft-release
  path. It never loops or sleeps. Exit 75
  means the fallback is queued, running, or not visible yet; run `status` again
  later. A failed run prints `gh run view --log-failed` output before returning.
- Add `--dry-run` to any command for read-only checks. It does not write release
  state, package, upload, dispatch, or download assets.

Resumable state is ignored under `build/release-state/` and keyed by version,
tag commit, candidate source fingerprint, and workflow correlation key.
Completed package, upload, fallback, and asset-verification steps are reused.
Do not delete state during an active release. Doctor, publish, and status use a
machine-wide lock below a private, user-owned directory. The lock launcher uses
`O_NOFOLLOW`, rejects hard links and non-regular files, and validates the
inherited file descriptor before release helpers run. The kernel releases
ownership on exit or SIGKILL; another live release command is rejected without
deleting release artifacts.

The no-network state-machine regression test is
`./script/tests/release_flow_test.sh`; it covers pending, failed, dry-run, stale
state, and strict checksum parsing without dispatching or publishing anything.

## Signing boundary

Public releases remain fixed self-signed and non-notarized. The canonical public
certificate fingerprints are in `script/release_identity.sh`; DMG verification
rejects the same display name with a different certificate. The canonical
fingerprint was independently extracted from the published v0.4.0 DMG.
Release DMGs also carry a code-signed commit/source-fingerprint attestation;
download verification must match it to the tagged state. GitHub operations are
bound to `tensornull/LexiRay`, and new releases remain draft until uploaded
assets pass checksum verification.

The old `build/release-signing.keychain-db` has an unknown random password and is
not recoverable. `doctor` removes only this repository's exact keychain path from
the search list without opening or deleting it. Never try to unlock it, run
`security show-keychain-info` on it, or enter the macOS login password for it.

If the original P12 is recovered, import it once through macOS Keychain Access
into the login keychain. Do not put its password in a command, shell profile,
agent message, tracked file, or repo state. Configure the imported private key's
Access Control for `/usr/bin/codesign` during that one-time setup so unattended
publication does not open a key-access dialog. Then explicitly run the supervised
one-time probe `./script/authorize_local_release_identity.sh`. Normal doctor never
invokes an interactive probe: it performs a Security-framework key-use check with
authentication UI disabled. If the current private key cannot sign immediately,
doctor clears the readiness marker and selects GitHub fallback instead of allowing
`codesign` to open a password dialog. Local publication is selected only when the
exact canonical SHA-1/SHA-256 certificate pair and its signing key pass that check.
If they do not, leave the key unused and use the GitHub fallback. Do not generate a
new release identity.

The shell import helper is restricted to GitHub Actions. It accepts repository
secrets only on the ephemeral fallback runner and verifies the canonical public
fingerprint before signing.

## Resuming a fallback

`publish` records the dispatch before returning exit 75. `status` discovers the
run by its correlation key, then reports one of:

- pending: no side effect; run `status` later;
- failed: failed-step logs are printed and the state is marked retryable;
- succeeded: local handoff is rechecked, then the private artifact's
  `.sha256`, DMG signature, bundle metadata, leaf certificate, designated
  requirement, entitlements, and source attestation are independently verified
  before draft upload and publication.

A dispatch or artifact that is not visible remains `uncertain`, even after five
minutes. Only an observed completed run with a non-success conclusion, or a
downloaded artifact that explicitly fails verification, becomes `failed` and
retryable.

After correcting a logged fallback failure, rerun `publish`. It reuses completed
local/state steps and dispatches only a new failed fallback attempt. Never blindly
rerun a GitHub job without inspecting the failure output.

Release notes and README must continue to state that the DMG is self-signed,
non-notarized, may trigger Gatekeeper, and should be checked against its
published `.sha256` file.

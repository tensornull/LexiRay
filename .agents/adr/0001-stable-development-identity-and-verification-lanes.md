# ADR 0001: Stable Development Identity and Verification Lanes

Status: Accepted

## Context

LexiRay depends on a stable macOS code identity for TCC and Login Items. A
normal build previously generated a new same-name self-signed certificate when
the login keychain was unavailable. Sandboxed automation could therefore
mistake an inaccessible keychain for a missing identity and silently rotate the
app identity. Separately, isolated GUI acceptance replaced `SMAppService` with
a fake, so it could not detect a real Background Task Management `notFound`
state. Swift CodeQL also added roughly forty minutes to release PR latency.

## Decision

- Normal permission-sensitive builds use the repository-pinned development
  certificate SHA-1/SHA-256 pair and fail closed. They never create, import,
  trust, delete, or rotate a certificate.
- CI/unit tests use unsigned or ad hoc builds and never access Keychain, TCC, or
  Login Items. Public releases retain their separate fixed self-signed identity.
- Login Item/signing/install changes, and every release, require a reversible
  real-system probe against `/Applications/LexiRay.app`. Test data and defaults
  remain isolated; the probe registers at most once and restores the observed
  initial off state.
- Installed-app Computer Use is change-scoped. Candidate creation derives the
  required scenarios from changed product paths and freezes the canonical,
  ordered matrix in the source-bound receipt. Handoff cannot add, remove, or
  reorder scenarios afterward. `launch` is always required; Login Item changes
  additionally require the actionable isolated `.notFound` Settings state.
  The real-system probe remains independent and cannot be replaced by that
  isolated UI state.
- Every acceptance process uses an acceptance-root-owned preferences home and
  bypasses the shared preferences daemon. `AcceptanceProfile` validates
  `HOME`, `CFFIXED_USER_HOME`, and `CFPREFERENCES_AVOID_DAEMON` before any
  acceptance store is constructed; harnesses never use the `defaults` CLI.
- Ordinary changes run in a dedicated linked worktree. The primary checkout is
  reserved for synchronization and release work.
- Swift CodeQL runs weekly or manually. It is diagnostic and non-blocking;
  ordinary CI remains the required exact-commit gate.
- No LaunchAgent fallback is installed. Native ServiceManagement failures are
  surfaced with the original error and fail closed.

An intentional development-identity rotation requires a reviewed change to the
public fingerprints and invalidates prior source-bound acceptance evidence.

## Verification lanes

1. **CI lane** — context checks, control-plane tests, and full unsigned Xcode
   tests only when Swift/build inputs changed.
2. **Local permission lane** — exact development identity, candidate receipt,
   canonical installation, real Login Item probe, and Computer Use.
3. **Release lane** — exact release identity plus the local permission-lane
   handoff and published-asset verification.

## Glossary

- **App Identity**: bundle ID, code requirement, certificate, and installed path
  that macOS uses to associate permissions and background records.
- **Signing Identity**: a certificate/private-key pair capable of signing code.
- **Login Item Record**: Background Task Management state managed through
  `SMAppService`.
- **Candidate**: source-fingerprint-bound workspace app that passed local gates.
- **Source Fingerprint**: digest of app, test, workflow, and verification inputs.
- **Acceptance Profile**: isolated data root, defaults suite, fixtures, and mock
  provider used by automated acceptance.
- **Evidence State**: `compiled`, `unit verified`, `GUI verified`, `installed
  verified`, `Computer Use verified`, or `released verified`.
- **Worktree**: a linked checkout with its own branch and build/evidence roots.

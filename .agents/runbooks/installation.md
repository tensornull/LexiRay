# Installed-App Preview

Development and installation are separate stages. The workspace build is the
candidate; `/Applications/LexiRay.app` is updated only after that exact
candidate passes verification.

## Workspace stage

- Build/run through `script/build_and_run.sh` at
  `build/DerivedData/Build/Products/Debug/LexiRay.app`.
- The workspace command must not copy, remove, or alter `/Applications` or
  `~/Applications`.
- Do not run a non-canonical app alongside the candidate; it can steal hotkeys,
  Accessibility targeting, or TCC identity.

## Install stage

For an app-binary change, invoke the
`lexiray-install-applications` skill automatically after
`./script/verify.sh candidate`. Docs/tests-only changes stop without install.
The install helper is the only allowed writer of `/Applications/LexiRay.app`.

```bash
./script/install_applications.sh
```

The helper must:

1. Require the current source fingerprint's candidate receipt.
2. Reuse the receipt's workspace bundle; never rebuild inside installation.
3. Stage with `ditto` beside the destination and verify `codesign --deep
   --strict`, authority, version/build, CDHash, executable hash, leaf
   certificate SHA-256, designated requirement, and entitlements hash.
4. Terminate only LexiRay processes whose executable path was positively
   identified.
5. Use identity-bound `RENAME_SWAP` to exchange an existing app, or
   `RENAME_EXCL` for a first install so an object appearing after the
   shell-level guard is rejected atomically. Keep a unique transaction marker
   containing both candidate and previous CDHash/executable/root-object
   identities. Reconcile pre-swap, post-swap, committed, ordinary-failure,
   signal, and SIGKILL states from those identities. An unknown identity
   preserves both bundles and the marker; it never guesses or deletes either
   copy.
6. Refresh Launch Services, launch the installed bundle, verify executable
   path, PID plus kernel start time, authority, version/build, and CDHash, and
   seal the automatically presented main-window capture before returning
   control for Computer Use.
7. Create the installed acceptance data root and defaults suite uniquely from
   the install transaction UUID. Directory creation must be exclusive; never
   delete or reuse a path-derived acceptance root. Mark the receipt installed
   only after all checks pass; remove the swapped-out backup and transaction
   marker only after successful validation. Serialize installers with the
   repository install lock.

Do not use `sudo` by default, reset TCC, touch user data, or describe a Debug
preview as a public release. A permission error is a blocker, not a reason to
weaken the destination or signature checks.

Continue with the installed-app procedure in `gui-acceptance.md`. Report the
receipt, installed identity, version/build, CDHash, running path/PID, rollback
result if applicable, and Computer Use result.

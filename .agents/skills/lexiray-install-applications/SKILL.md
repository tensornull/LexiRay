---
name: lexiray-install-applications
description: Install the current receipt-verified LexiRay candidate into `/Applications/LexiRay.app` and launch it with isolated acceptance data. Use automatically after app-binary changes pass candidate verification, or when the user asks to install, replace, update, launch, or preview the local Applications copy.
---

# LexiRay Applications Install Skill

Install only the app recorded by the current source fingerprint's candidate
receipt. This is a local preview, not a release, tag, or notarization workflow.

## Safety Boundary

- App-binary changes install automatically after `script/verify.sh candidate`
  passes. Do not ask for an extra confirmation; docs/tests-only changes do not
  install.
- The candidate receipt must match the current source fingerprint. Never build
  during installation or install an unverified/stale bundle.
- Do not use `sudo` by default. If `/Applications` permissions block the
  replacement, report the exact permission error and ask the user how to proceed.
- Never read, back up, reset, or modify `~/.lexiray`, the production defaults
  domain, TCC, provider secrets, or release artifacts.
- Do not claim this is a release build. The installed copy is a Debug build
  signed with `LexiRay Local Development`.
- If another LexiRay build/test/CI command is currently running, wait for it to
  finish or report that it is blocking installation. Do not kill unrelated
  build processes.

## Install Workflow

Run the sole `/Applications` writer from the repository root:

```bash
./script/install_applications.sh
```

The helper rejects active builds and stale receipts, stages and verifies the
candidate, uses identity-bound `RENAME_SWAP` or first-install `RENAME_EXCL`
plus a recoverable transaction marker, registers Launch Services, verifies
version/build/authority/CDHash/executable hash, and rolls back on failure. Its
interprocess lock prevents concurrent installers. Installed acceptance roots
and defaults suites are transaction-unique and are never deleted or reused by
path alone.
For Login Item, signing, or installation changes, it runs the receipt-required
real `SMAppService` probe before the normal acceptance process. The probe uses
isolated data/defaults, mutates only LexiRay's Login Item record, registers at
most once, and restores an observed initial off state. A blocked or failed
probe is not installed verification.
It launches the installed app with an ignored acceptance data root and
independent defaults suite for Computer Use; it never launches the installed
app against real user data during automated acceptance.
Before returning, it also seals the `launch` capture from the automatically
presented main window. Later `capture-computer-use launch` revalidates and
returns that evidence; it cannot replace it with a manually opened window.

After installation, use Computer Use on `/Applications/LexiRay.app` to exercise
every scenario in the candidate-frozen, change-scoped installed matrix. After placing the app in the
required state for each scenario, capture only the receipt-bound PID-owned
window through the repository helper (pass a CGWindow ID only when automatic
selection is ambiguous):

Target Computer Use by the display name `LexiRay` only after the receipt has
validated that its PID is the sole running LexiRay process. Do not target the
bundle ID or full app path: the Computer Use resolver may launch an additional
non-acceptance instance and make the bundle ambiguous. Revalidate the sole
receipt-bound process before every capture; an extra LexiRay process fails the
capture closed.

```bash
./script/acceptance_receipt.sh computer-use-matrix
./script/acceptance_receipt.sh capture-computer-use <scenario> [window-id]
```

While the acceptance PID is still running, generate the controlled contact
sheet and source/app/process-bound manifest, inspect the contact sheet, then
record the result:

```bash
manifest="$(./script/acceptance_receipt.sh write-computer-use-manifest)"
./script/acceptance_receipt.sh mark-computer-use passed "$manifest"
```

Quit the acceptance-profile process when finished. Leave the installed app in
place for the user. Arbitrary scenarios, external screenshot directories,
external contact sheets, or free-form notes are not passing evidence; follow
`.agents/runbooks/gui-acceptance.md` for the evidence contract.

## Handoff

Report:

- The candidate receipt and source fingerprint.
- Whether `/Applications/LexiRay.app` was replaced.
- The installed app signing authority.
- The running installed app path and PID.
- Any non-fatal local toolchain noise, such as CoreSimulator warnings, without
  treating it as a blocker when the macOS build succeeds.

Do not include git stage/commit/push directives unless the user separately asks
for git operations.

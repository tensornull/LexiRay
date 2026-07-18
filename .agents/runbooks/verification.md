# Verification Runbook

Use the repository entry points; do not assemble an alternative build/test
pipeline. Verification evidence belongs to the current source fingerprint.

## Entry points

```bash
./script/preflight.sh change
./script/verify.sh changed
./script/verify.sh candidate
./script/verify.sh pr
```

These gates run registered script control-plane tests through the bounded
parallel `script/run_control_plane_tests.sh` entry point. Do not replace it with
a serial per-test loop in CI or local verification.

- `changed`: run format, incremental build, relevant unit tests, and affected
  GUI scenarios after an edit batch.
- `candidate`: run the full local gate and produce a signed workspace build. If
  the change is UI-affecting, also run the complete GUI suite and create its
  screenshot/contact-sheet evidence.
- `pr`: require current inspected candidate evidence (and installed-app Computer
  Use evidence for app-binary changes), then run context lint and the
  CI-equivalent gate. It may reuse evidence only when the source fingerprint
  matches.

Never describe a transport result, compile, mock response, or green scenario
exit code as broader evidence than it is.

## Acceptance receipt

Candidate receipts are ignored files named for the source fingerprint under
`build/acceptance/`. Use the helper rather than parsing or editing JSON:

```bash
./script/acceptance_receipt.sh fingerprint
./script/acceptance_receipt.sh path
./script/acceptance_receipt.sh require-candidate
./script/acceptance_receipt.sh require-handoff
./script/acceptance_receipt.sh field <keypath>
./script/acceptance_receipt.sh mark-gui-inspected passed <contact-sheet-path>
./script/acceptance_receipt.sh require-login-item-probe
./script/acceptance_receipt.sh mark-computer-use passed <computer-use-manifest.json>
```

The canonical installer records the exact `/Applications` path and live
acceptance-profile PID. Do not call `mark-installed` manually.

Login Item, signing, installation, and release changes require the reversible
real-system probe before installed acceptance. A passing manifest is bound to
the source fingerprint, installed CDHash/certificate/requirement, OS version,
and initial/registered/final states. Mock status coverage is never real-system
evidence.

Use `failed` or `blocked` instead of `passed` when appropriate. Any source
change creates a different fingerprint and invalidates earlier candidate,
install, and Computer Use evidence.

## Coverage routing

- Docs/context-only: context lint plus the narrow relevant checks.
- Model/store/service: format, build, and the affected unit-test classes.
- Visible UI, panel, hotkey, selection, OCR, permission, speech, streaming, or
  window behavior: all of the above plus affected GUI scenarios each iteration;
  full GUI suite and inspected contact sheet at candidate.
- Permission, TCC, signing, installation, packaging, or release: use only the
  matching repository runbook and scripts.

Before handoff, run an adversarial pass: look for stale evidence, a real path
the mock did not cover, data touched outside the acceptance profile, interrupted
cleanup, failed install rollback, wrong running app, or a signature/version
mismatch.

Report checks run, scenario names, artifact directory, receipt path, checks
skipped or blocked, and remaining risk.

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lexiray-control-plane-test.XXXXXX")"
PROBE="$ROOT_DIR/script/.fingerprint-probe-$$"
trap 'rm -rf "$WORK_DIR"; rm -f "$PROBE"' EXIT

cd "$ROOT_DIR"

bash -n \
  script/acceptance_receipt.sh \
  script/build_and_run.sh \
  script/ci_local.sh \
  script/context_lint.sh \
  script/preflight.sh \
  script/release_check.sh \
  script/verify_release_dmg.sh \
  script/verify.sh

rg -F '[[ -n "$EXPECTED_COMMIT" && "$attested_commit" != "$EXPECTED_COMMIT" ]]' \
  script/verify_release_dmg.sh >/dev/null || {
  echo "DMG verifier does not independently gate the optional source commit expectation" >&2
  exit 1
}
rg -F '[[ -n "$EXPECTED_FINGERPRINT" && "$attested_fingerprint" != "$EXPECTED_FINGERPRINT" ]]' \
  script/verify_release_dmg.sh >/dev/null || {
  echo "DMG verifier does not independently gate the optional source fingerprint expectation" >&2
  exit 1
}

if rg -n '/usr/bin/plutil[[:space:]]+-lint|X{6}\.' script/acceptance_receipt.sh >/dev/null 2>&1; then
  echo "acceptance receipts must use JSON-capable validation and portable mktemp templates" >&2
  exit 1
fi

before="$(./script/acceptance_receipt.sh fingerprint)"
touch "$PROBE"
during="$(./script/acceptance_receipt.sh fingerprint)"
rm -f "$PROBE"
after="$(./script/acceptance_receipt.sh fingerprint)"
[[ "$before" != "$during" ]] || {
  echo "source fingerprint did not change for a new script input" >&2
  exit 1
}
[[ "$before" == "$after" ]] || {
  echo "source fingerprint did not restore after removing the probe" >&2
  exit 1
}

expected_path="$ROOT_DIR/build/acceptance/candidate-$before.json"
[[ "$(./script/acceptance_receipt.sh path)" == "$expected_path" ]]

if LEXIRAY_ACCEPTANCE_DIR="$WORK_DIR/empty-acceptance" \
  ./script/acceptance_receipt.sh require-candidate >/dev/null 2>&1; then
  echo "missing candidate receipt was accepted" >&2
  exit 1
fi

if rg -n 'install_to_applications|INSTALLED_APP_BUNDLE|rm -rf ["'\"']?/Applications|cp .*[/]Applications' \
  script/build_and_run.sh >/dev/null 2>&1; then
  echo "build_and_run.sh contains an /Applications write path" >&2
  exit 1
fi

if rg -n '(^|[[:space:]/])security([[:space:]]|$)' script/preflight.sh >/dev/null 2>&1; then
  echo "preflight.sh must not invoke security/keychain commands" >&2
  exit 1
fi

rg -F -- '--diff-filter=ACDMRTUXB' script/verify.sh >/dev/null || {
  echo "verify.sh does not route deleted files through changed-scope verification" >&2
  exit 1
}

rg -F '[[ "$installed" == /Applications/LexiRay.app ]]' script/acceptance_receipt.sh >/dev/null || {
  echo "mark-installed is not bound to the canonical Applications path" >&2
  exit 1
}

rg -F 'validate_installed_acceptance_process' script/acceptance_receipt.sh >/dev/null || {
  echo "Computer Use evidence is not bound to a live isolated installed process" >&2
  exit 1
}

rg -F 'capture_installed_launch' script/acceptance_receipt.sh >/dev/null || {
  echo "installation does not seal the automatically presented main window" >&2
  exit 1
}
rg -F 'Launch evidence must be sealed during canonical installation.' \
  script/acceptance_receipt.sh >/dev/null || {
  echo "launch evidence can be replaced after installation" >&2
  exit 1
}

rg -F 'source_fingerprint -string "$SOURCE_FINGERPRINT"' script/ui/run.sh >/dev/null || {
  echo "GUI evidence is not bound to the current source fingerprint" >&2
  exit 1
}
rg -F 'app_cdhash -string "$APP_CDHASH"' script/ui/run.sh >/dev/null || {
  echo "GUI evidence is not bound to the candidate CDHash" >&2
  exit 1
}

rg -F '[[ -z "${LEXIRAY_REUSE_GUI_ARTIFACT_DIR:-}" ]]' script/verify.sh >/dev/null || {
  echo "explicit GUI artifact reuse can be shadowed by a stale automated candidate" >&2
  exit 1
}

rg -F 'let sourceKindValues = sourceKinds.flatMap' script/acceptance_evidence.swift >/dev/null || {
  echo "OCR source evidence does not inspect every AX element carrying the source badge identifier" >&2
  exit 1
}

rg -F 'sourceKindValues.contains("OCR")' script/acceptance_evidence.swift >/dev/null || {
  echo "OCR source evidence is not matched exactly against the AX badge" >&2
  exit 1
}

rg -F 'sourceKinds.contains(where: { axVisibleText($0).contains("Accessibility") })' script/acceptance_evidence.swift >/dev/null || {
  echo "Selection source evidence does not inspect every AX element carrying the source badge identifier" >&2
  exit 1
}

rg -F '"ocr_result_display_1", "ocr_result_display_2"' script/acceptance_evidence.swift >/dev/null || {
  echo "Computer Use OCR result evidence is not bound to the floating panel AX window" >&2
  exit 1
}

rg -F 'grep -Fxf "$SCENARIOS" "$AVAILABLE_SCENARIOS"' script/verify.sh >/dev/null || {
  echo "targeted GUI scenarios are not restored to canonical execution order" >&2
  exit 1
}

mkdir -p "$WORK_DIR/screenshots"
cp LexiRay/Resources/Assets.xcassets/AppIcon.appiconset/LexiRay-256.png \
  "$WORK_DIR/screenshots/example.png"
./script/make_contact_sheet.swift \
  "$WORK_DIR/screenshots" \
  "$WORK_DIR/screenshots/contact-sheet.png" >/dev/null
[[ -s "$WORK_DIR/screenshots/contact-sheet.png" ]]

./script/context_lint.sh >/dev/null
echo "VERIFICATION_CONTROL_PLANE_TEST_PASS"

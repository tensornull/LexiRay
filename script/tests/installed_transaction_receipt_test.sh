#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EVIDENCE_DIR="$ROOT_DIR/build/acceptance/installed-transaction-test-$$"
RECEIPT="$EVIDENCE_DIR/candidate.json"
TRANSACTION_ID="00000000-0000-4000-8000-000000000123"
trap 'rm -rf "$EVIDENCE_DIR"' EXIT

mkdir -p "$EVIDENCE_DIR"
LEXIRAY_ACCEPTANCE_DIR="$EVIDENCE_DIR" \
  LEXIRAY_ACCEPTANCE_LIBRARY_ONLY=1 \
  source "$ROOT_DIR/script/acceptance_receipt.sh"

fingerprint="$(printf '1%.0s' {1..64})"
cdhash="$(printf '2%.0s' {1..40})"
executable_hash="$(printf '3%.0s' {1..64})"
certificate_hash="$(printf '4%.0s' {1..64})"
requirement_hash="$(printf '5%.0s' {1..64})"
entitlements_hash="$(printf '6%.0s' {1..64})"
expected_acceptance_root="$ROOT_DIR/build/acceptance-data/installed-$fingerprint-$TRANSACTION_ID"
expected_defaults_suite="io.github.tensornull.lexiray.acceptance.installed.${fingerprint:0:16}.${TRANSACTION_ID//-/}"

/usr/bin/plutil -create xml1 "$RECEIPT"
/usr/bin/plutil -insert app -dictionary -- "$RECEIPT"
/usr/bin/plutil -insert verification -dictionary -- "$RECEIPT"
for pair in \
  "source_fingerprint:$fingerprint" \
  "version:0.0.0" \
  "build:1" \
  "app.cdhash:$cdhash" \
  "app.authority:Test Authority" \
  "app.executable_sha256:$executable_hash" \
  "app.certificate_sha256:$certificate_hash" \
  "app.designated_requirement_sha256:$requirement_hash" \
  "app.entitlements_sha256:$entitlements_hash"; do
  /usr/bin/plutil -insert "${pair%%:*}" -string "${pair#*:}" -- "$RECEIPT"
done
for key in \
  installed installed_path installed_cdhash installed_certificate_sha256 \
  installed_designated_requirement_sha256 installed_entitlements_sha256 installed_pid \
  installed_process_start_time_us \
  installed_acceptance_root installed_defaults_suite install_transaction_id installed_at \
  computer_use computer_use_evidence computer_use_evidence_sha256 computer_use_scenarios \
  computer_use_screenshots_manifest computer_use_screenshots_sha256 computer_use_contact_sheet \
  computer_use_contact_sheet_sha256 computer_use_scenario_screenshots_sha256 \
  computer_use_provenance_manifest computer_use_provenance_manifest_sha256 computer_use_at; do
  /usr/bin/plutil -insert "verification.$key" -string "" -- "$RECEIPT"
done

require_candidate() { printf '%s\n' "$RECEIPT"; }
verify_app() { :; }
validate_installed_acceptance_process() {
  [[ "$3" == "$expected_acceptance_root" && "$4" == "$expected_defaults_suite" ]]
}
installed_acceptance_process_start_time() {
  [[ "$3" == "$expected_acceptance_root" && "$4" == "$expected_defaults_suite" ]]
  printf '%s\n' 1720656000123456
}
app_cdhash() { printf '%s\n' "$cdhash"; }
app_version() { printf '%s\n' 0.0.0; }
app_build() { printf '%s\n' 1; }
app_authority() { printf '%s\n' 'Test Authority'; }
app_executable_sha256() { printf '%s\n' "$executable_hash"; }
app_certificate_sha256() { printf '%s\n' "$certificate_hash"; }
app_designated_requirement_sha256() { printf '%s\n' "$requirement_hash"; }
app_entitlements_sha256() { printf '%s\n' "$entitlements_hash"; }
app_matches_receipt() { return 0; }
capture_installed_launch() {
  local provenance="$EVIDENCE_DIR/install-launch.json"
  printf '{"kind":"install-launch-test"}\n' >"$provenance"
  printf '%s\n' "$provenance"
}

if mark_installed /Applications/LexiRay.app 4242 not-a-uuid >/dev/null 2>&1; then
  echo "mark-installed accepted a malformed transaction ID" >&2
  exit 1
fi
[[ "$(plist_value "$RECEIPT" verification.install_transaction_id)" == "" ]]

mark_installed /Applications/LexiRay.app 4242 "$TRANSACTION_ID" >/dev/null
[[ "$(plist_value "$RECEIPT" verification.installed)" == passed ]]
[[ "$(plist_value "$RECEIPT" verification.install_transaction_id)" == "$TRANSACTION_ID" ]]
[[ "$(plist_value "$RECEIPT" verification.installed_path)" == /Applications/LexiRay.app ]]
[[ "$(plist_value "$RECEIPT" verification.installed_process_start_time_us)" == 1720656000123456 ]]
[[ "$(plist_value "$RECEIPT" verification.installed_acceptance_root)" == "$expected_acceptance_root" ]]
[[ "$(plist_value "$RECEIPT" verification.installed_defaults_suite)" == "$expected_defaults_suite" ]]
[[ -s "$EVIDENCE_DIR/install-launch.json" ]]
[[ -z "$(find "$EVIDENCE_DIR" -maxdepth 1 -name '.update-*' -print -quit)" ]]

installed_transaction_valid "$TRANSACTION_ID" /Applications/LexiRay.app >/dev/null
if installed_transaction_valid 00000000-0000-4000-8000-000000000124 \
  /Applications/LexiRay.app >/dev/null 2>&1; then
  echo "installed-transaction-valid accepted a different transaction ID" >&2
  exit 1
fi
if installed_transaction_valid "$TRANSACTION_ID" /Applications/Other.app >/dev/null 2>&1; then
  echo "installed-transaction-valid accepted a different app path" >&2
  exit 1
fi
app_matches_receipt() { return 1; }
if installed_transaction_valid "$TRANSACTION_ID" /Applications/LexiRay.app >/dev/null 2>&1; then
  echo "installed-transaction-valid accepted a changed app identity" >&2
  exit 1
fi

echo "INSTALLED_TRANSACTION_RECEIPT_TEST_PASS"

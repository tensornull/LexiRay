#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GUI_ROOT="$ROOT_DIR/build/ui-artifacts"
EVIDENCE_DIR="$GUI_ROOT/gui-evidence-manifest-test-$$"
PREFIX_DIR="$ROOT_DIR/build/ui-artifacts-prefix-test-$$"
ACCEPTANCE_TEST_DIR="$ROOT_DIR/build/acceptance/gui-evidence-manifest-test-$$"
OUTSIDE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lexiray-gui-evidence-test.XXXXXX")"
ICON="$ROOT_DIR/LexiRay/Resources/Assets.xcassets/AppIcon.appiconset/LexiRay-256.png"
TEST_FINGERPRINT="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
TEST_HASH="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
APP="$OUTSIDE_DIR/Fake.app"

cleanup() {
  rm -rf "$EVIDENCE_DIR" "$PREFIX_DIR" "$ACCEPTANCE_TEST_DIR" "$OUTSIDE_DIR"
}
trap cleanup EXIT

mkdir -p "$GUI_ROOT" "$EVIDENCE_DIR" "$PREFIX_DIR" "$ACCEPTANCE_TEST_DIR" "$APP"
printf '%s\n' "$TEST_FINGERPRINT" >"$APP.source-fingerprint"

export LEXIRAY_ACCEPTANCE_DIR="$ACCEPTANCE_TEST_DIR"
export LEXIRAY_ACCEPTANCE_LIBRARY_ONLY=1
source "$ROOT_DIR/script/acceptance_receipt.sh"
unset LEXIRAY_ACCEPTANCE_LIBRARY_ONLY

# Candidate app and L3 identity are not under test here. Keep all receipt path,
# plist, hash, and GUI evidence validation real.
source_fingerprint() { printf '%s\n' "$TEST_FINGERPRINT"; }
l3_valid() { return 0; }
verify_app() { [[ -d "$1" ]]; }
app_authority() { printf 'LexiRay Test Identity\n'; }
app_cdhash() { printf '0123456789abcdef0123456789abcdef01234567\n'; }
app_version() { printf '1.0.0\n'; }
app_build() { printf '1\n'; }
app_bundle_id() { printf 'io.github.tensornull.lexiray\n'; }
app_executable_sha256() { printf '%s\n' "$TEST_HASH"; }
app_certificate_sha256() { printf '%s\n' "$TEST_HASH"; }
app_designated_requirement() { printf 'identifier io.github.tensornull.lexiray\n'; }
app_designated_requirement_sha256() { printf '%s\n' "$TEST_HASH"; }
app_entitlements_sha256() { printf '%s\n' "$TEST_HASH"; }

scenario_names="$("$ROOT_DIR/script/ui/run.sh" --list | paste -sd, -)"

make_bundle() {
  local dir="$1"
  local screenshot="$dir/window.png"
  local screenshots_manifest="$dir/gui-screenshots.sha256"
  local plist="$dir/.gui-run.plist"
  local scenario

  mkdir -p "$dir"
  cp "$ICON" "$screenshot"
  cp "$ICON" "$dir/contact-sheet.png"
  while IFS= read -r scenario; do
    printf 'PASS  %s\n' "$scenario"
  done < <("$ROOT_DIR/script/ui/run.sh" --list) >"$dir/results.txt"
  printf '%s  %s\n' "$(sha256_file "$screenshot")" "$screenshot" >"$screenshots_manifest"

  /usr/bin/plutil -create xml1 "$plist"
  /usr/bin/plutil -insert schema_version -integer 1 -- "$plist"
  /usr/bin/plutil -insert kind -string gui-run -- "$plist"
  /usr/bin/plutil -insert source_fingerprint -string "$TEST_FINGERPRINT" -- "$plist"
  /usr/bin/plutil -insert app_path -string "$APP" -- "$plist"
  /usr/bin/plutil -insert app_cdhash -string "$(app_cdhash "$APP")" -- "$plist"
  /usr/bin/plutil -insert app_executable_sha256 -string "$TEST_HASH" -- "$plist"
  /usr/bin/plutil -insert app_certificate_sha256 -string "$TEST_HASH" -- "$plist"
  /usr/bin/plutil -insert app_designated_requirement_sha256 -string "$TEST_HASH" -- "$plist"
  /usr/bin/plutil -insert app_entitlements_sha256 -string "$TEST_HASH" -- "$plist"
  /usr/bin/plutil -insert scenarios -string "$scenario_names" -- "$plist"
  /usr/bin/plutil -insert results_sha256 -string "$(sha256_file "$dir/results.txt")" -- "$plist"
  /usr/bin/plutil -insert screenshots_manifest -string "$screenshots_manifest" -- "$plist"
  /usr/bin/plutil -insert screenshots_manifest_sha256 \
    -string "$(sha256_file "$screenshots_manifest")" -- "$plist"
  /usr/bin/plutil -insert screenshot_count -integer 1 -- "$plist"
  /usr/bin/plutil -insert created_at -string '2026-07-11T00:00:00Z' -- "$plist"
  /usr/bin/plutil -convert json -r -o "$dir/gui-run.json" -- "$plist"
  rm -f "$plist"
}

expect_rejected() {
  local message="$1"
  shift
  if ("$@" >/dev/null 2>&1); then
    echo "$message" >&2
    exit 1
  fi
}

VALID_BUNDLE="$EVIDENCE_DIR/valid"
OUTSIDE_BUNDLE="$OUTSIDE_DIR/outside"
PREFIX_BUNDLE="$PREFIX_DIR/prefix"
make_bundle "$VALID_BUNDLE"
make_bundle "$OUTSIDE_BUNDLE"
make_bundle "$PREFIX_BUNDLE"

require_candidate_gui_evidence_paths \
  "$VALID_BUNDLE" "$VALID_BUNDLE/contact-sheet.png" \
  "$VALID_BUNDLE/results.txt" "$VALID_BUNDLE/gui-run.json" \
  "$VALID_BUNDLE/gui-screenshots.sha256"
verify_screenshot_manifest "$VALID_BUNDLE/gui-screenshots.sha256" 1 "$VALID_BUNDLE"

expect_rejected "GUI directory validator accepted /tmp evidence" \
  require_gui_artifact_directory "$OUTSIDE_BUNDLE"
expect_rejected "GUI directory validator accepted a lexical-prefix sibling" \
  require_gui_artifact_directory "$PREFIX_BUNDLE"

ln -s "$OUTSIDE_BUNDLE" "$EVIDENCE_DIR/component-link"
expect_rejected "GUI directory validator accepted a symlink component" \
  require_gui_artifact_directory "$EVIDENCE_DIR/component-link"

FILE_CASES="$EVIDENCE_DIR/file-cases"
mkdir -p "$FILE_CASES/non-regular"
: >"$FILE_CASES/empty.txt"
ln -s "$OUTSIDE_BUNDLE/results.txt" "$FILE_CASES/final-link.txt"
expect_rejected "GUI file validator accepted an empty file" \
  require_gui_artifact_file "$FILE_CASES/empty.txt"
expect_rejected "GUI file validator accepted a non-regular file" \
  require_gui_artifact_file "$FILE_CASES/non-regular"
expect_rejected "GUI file validator accepted a final symlink" \
  require_gui_artifact_file "$FILE_CASES/final-link.txt"
expect_rejected "GUI file validator accepted an outside file" \
  require_gui_artifact_file "$OUTSIDE_BUNDLE/results.txt"

expect_rejected "Candidate writer accepted an outside GUI artifact directory" \
  write_candidate "$APP" passed "$OUTSIDE_BUNDLE" "$OUTSIDE_BUNDLE/contact-sheet.png"
expect_rejected "Candidate writer accepted a lexical-prefix GUI artifact directory" \
  write_candidate "$APP" passed "$PREFIX_BUNDLE" "$PREFIX_BUNDLE/contact-sheet.png"
expect_rejected "Candidate writer accepted a symlinked GUI artifact directory" \
  write_candidate "$APP" passed "$EVIDENCE_DIR/component-link" \
  "$EVIDENCE_DIR/component-link/contact-sheet.png"

OUTSIDE_PNG="$OUTSIDE_DIR/outside.png"
cp "$ICON" "$OUTSIDE_PNG"
BAD_SCREENSHOT_BUNDLE="$EVIDENCE_DIR/outside-screenshot"
make_bundle "$BAD_SCREENSHOT_BUNDLE"
printf '%s  %s\n' "$(sha256_file "$OUTSIDE_PNG")" "$OUTSIDE_PNG" \
  >"$BAD_SCREENSHOT_BUNDLE/gui-screenshots.sha256"
/usr/bin/plutil -replace screenshots_manifest_sha256 \
  -string "$(sha256_file "$BAD_SCREENSHOT_BUNDLE/gui-screenshots.sha256")" -- \
  "$BAD_SCREENSHOT_BUNDLE/gui-run.json"
expect_rejected "Candidate writer accepted a screenshot outside its GUI run directory" \
  write_candidate "$APP" passed "$BAD_SCREENSHOT_BUNDLE" \
  "$BAD_SCREENSHOT_BUNDLE/contact-sheet.png"

SYMLINK_SCREENSHOT_BUNDLE="$EVIDENCE_DIR/symlink-screenshot"
make_bundle "$SYMLINK_SCREENSHOT_BUNDLE"
rm -f "$SYMLINK_SCREENSHOT_BUNDLE/window.png"
ln -s "$OUTSIDE_PNG" "$SYMLINK_SCREENSHOT_BUNDLE/window.png"
printf '%s  %s\n' "$(sha256_file "$OUTSIDE_PNG")" \
  "$SYMLINK_SCREENSHOT_BUNDLE/window.png" \
  >"$SYMLINK_SCREENSHOT_BUNDLE/gui-screenshots.sha256"
/usr/bin/plutil -replace screenshots_manifest_sha256 \
  -string "$(sha256_file "$SYMLINK_SCREENSHOT_BUNDLE/gui-screenshots.sha256")" -- \
  "$SYMLINK_SCREENSHOT_BUNDLE/gui-run.json"
expect_rejected "Candidate writer accepted a final-symlink screenshot" \
  write_candidate "$APP" passed "$SYMLINK_SCREENSHOT_BUNDLE" \
  "$SYMLINK_SCREENSHOT_BUNDLE/contact-sheet.png"

RECEIPT="$(write_candidate "$APP" passed "$VALID_BUNDLE" "$VALID_BUNDLE/contact-sheet.png")"
require_candidate 0 >/dev/null

/usr/bin/plutil -replace verification.gui_artifact_dir -string "$OUTSIDE_BUNDLE" -- "$RECEIPT"
expect_rejected "Candidate reader accepted an outside GUI artifact directory" require_candidate 0
/usr/bin/plutil -replace verification.gui_artifact_dir -string "$VALID_BUNDLE" -- "$RECEIPT"

MOVED_BUNDLE="$OUTSIDE_DIR/moved-valid"
mv "$VALID_BUNDLE" "$MOVED_BUNDLE"
ln -s "$MOVED_BUNDLE" "$VALID_BUNDLE"
expect_rejected "Candidate reader accepted a GUI artifact symlink swap" require_candidate 0
rm -f "$VALID_BUNDLE"
mv "$MOVED_BUNDLE" "$VALID_BUNDLE"

mv "$VALID_BUNDLE/window.png" "$OUTSIDE_DIR/moved-window.png"
ln -s "$OUTSIDE_DIR/moved-window.png" "$VALID_BUNDLE/window.png"
expect_rejected "Candidate reader accepted a final-symlink screenshot" require_candidate 0
rm -f "$VALID_BUNDLE/window.png"
mv "$OUTSIDE_DIR/moved-window.png" "$VALID_BUNDLE/window.png"
require_candidate 0 >/dev/null

printf 'tampered\n' >>"$VALID_BUNDLE/window.png"
expect_rejected "GUI screenshot manifest accepted a changed raw screenshot" \
  verify_screenshot_manifest "$VALID_BUNDLE/gui-screenshots.sha256" 1 "$VALID_BUNDLE"

printf 'not-a-real-png\n' >"$VALID_BUNDLE/window.png"
printf '%s  %s\n' "$(sha256_file "$VALID_BUNDLE/window.png")" "$VALID_BUNDLE/window.png" \
  >"$VALID_BUNDLE/gui-screenshots.sha256"
expect_rejected "GUI screenshot manifest accepted rehashed non-image bytes" \
  verify_screenshot_manifest "$VALID_BUNDLE/gui-screenshots.sha256" 1 "$VALID_BUNDLE"

echo "GUI_EVIDENCE_MANIFEST_TEST_PASS"

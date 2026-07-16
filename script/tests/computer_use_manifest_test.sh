#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EVIDENCE_DIR="$ROOT_DIR/build/acceptance/computer-use-manifest-test-$$"
fingerprint="$(printf '1%.0s' {1..64})"
transaction_id="11111111-1111-4111-8111-111111111111"
installed_at="2026-07-11T00:00:00Z"
manifest_created_at="2026-07-11T00:02:00Z"
CAPTURE_ROOT="$EVIDENCE_DIR/computer-use-captures-$fingerprint-$transaction_id"
RECEIPT="$EVIDENCE_DIR/receipt.json"
PROVENANCE_MANIFEST="$EVIDENCE_DIR/computer-use-provenance-$fingerprint-$transaction_id.sha256"
SCREENSHOTS_MANIFEST="$EVIDENCE_DIR/computer-use-screenshots-$fingerprint-$transaction_id.sha256"
CONTACT_SHEET="$EVIDENCE_DIR/computer-use-contact-sheet-$fingerprint-$transaction_id.png"
MANIFEST="$EVIDENCE_DIR/computer-use-$fingerprint-$transaction_id.json"
INPUT_DIR="$EVIDENCE_DIR/contact-input"
trap 'rm -rf "$EVIDENCE_DIR"' EXIT

mkdir -p "$CAPTURE_ROOT" "$INPUT_DIR"
LEXIRAY_ACCEPTANCE_DIR="$EVIDENCE_DIR" \
  LEXIRAY_ACCEPTANCE_LIBRARY_ONLY=1 \
  source "$ROOT_DIR/script/acceptance_receipt.sh"

cdhash="$(printf '2%.0s' {1..40})"
executable_hash="$(printf '3%.0s' {1..64})"
certificate_hash="$(printf '4%.0s' {1..64})"
requirement_hash="$(printf '5%.0s' {1..64})"
entitlements_hash="$(printf '6%.0s' {1..64})"
installed_pid=4242
installed_process_start=1752192000123456
installed_root="$ROOT_DIR/build/acceptance-data/installed-$fingerprint-$transaction_id"
installed_suite="io.github.tensornull.lexiray.acceptance.installed.${fingerprint:0:16}.${transaction_id//-/}"
installed_executable="/Applications/LexiRay.app/Contents/MacOS/LexiRay"
expected_arguments=(
  --lexiray-acceptance-profile
  --lexiray-acceptance-workspace-root "$ROOT_DIR"
  --lexiray-acceptance-root "$installed_root"
  --lexiray-acceptance-defaults-suite "$installed_suite"
)
arguments_hash="$(/usr/bin/swift "$ROOT_DIR/script/acceptance_evidence.swift" \
  arguments-hash -- "${expected_arguments[@]}")"

/usr/bin/swift - "$EVIDENCE_DIR" <<'SWIFT'
import AppKit
import CoreGraphics
import Foundation

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let scenarios = [
  "launch", "selection_hotkey", "source_editor", "language_direction", "speech_controls",
  "panel_visual_states", "ocr_result_display_1", "ocr_result_display_2",
  "ocr_multi_display"
]
for (index, scenario) in scenarios.enumerated() {
  let width = 240
  let height = 160
  guard let context = CGContext(
    data: nil,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
  ) else {
    exit(1)
  }
  let base = CGFloat(index + 1) / CGFloat(scenarios.count + 2)
  context.setFillColor(red: 0.08 + base * 0.3, green: 0.18, blue: 0.28 + base * 0.35, alpha: 1)
  context.fill(CGRect(x: 0, y: 0, width: width, height: height))
  for stripe in 0 ... index + 2 {
    context.setFillColor(red: 0.75, green: 0.25 + base * 0.4, blue: 0.18, alpha: 1)
    context.fill(CGRect(x: 12 + stripe * 28, y: 20 + stripe * 5, width: 14, height: 110))
  }
  guard let image = context.makeImage(),
        let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
  else {
    exit(1)
  }
  try data.write(
    to: outputDirectory.appending(path: "fixture-\(scenario).png"),
    options: .atomic
  )
}
SWIFT
/usr/bin/swift "$ROOT_DIR/script/acceptance_evidence.swift" png "$EVIDENCE_DIR"/fixture-*.png

make_receipt() {
  /usr/bin/plutil -create xml1 "$RECEIPT"
  /usr/bin/plutil -insert app -dictionary -- "$RECEIPT"
  /usr/bin/plutil -insert verification -dictionary -- "$RECEIPT"
  /usr/bin/plutil -insert source_fingerprint -string "$fingerprint" -- "$RECEIPT"
  /usr/bin/plutil -insert app.cdhash -string "$cdhash" -- "$RECEIPT"
  /usr/bin/plutil -insert app.executable_sha256 -string "$executable_hash" -- "$RECEIPT"
  /usr/bin/plutil -insert app.certificate_sha256 -string "$certificate_hash" -- "$RECEIPT"
  /usr/bin/plutil -insert app.designated_requirement_sha256 -string "$requirement_hash" -- "$RECEIPT"
  /usr/bin/plutil -insert app.entitlements_sha256 -string "$entitlements_hash" -- "$RECEIPT"
  /usr/bin/plutil -insert verification.installed_path -string /Applications/LexiRay.app -- "$RECEIPT"
  /usr/bin/plutil -insert verification.installed_pid -string "$installed_pid" -- "$RECEIPT"
  /usr/bin/plutil -insert verification.installed_process_start_time_us \
    -string "$installed_process_start" -- "$RECEIPT"
  /usr/bin/plutil -insert verification.installed_acceptance_root -string "$installed_root" -- "$RECEIPT"
  /usr/bin/plutil -insert verification.installed_defaults_suite -string "$installed_suite" -- "$RECEIPT"
  /usr/bin/plutil -insert verification.install_transaction_id -string "$transaction_id" -- "$RECEIPT"
  /usr/bin/plutil -insert verification.installed_at -string "$installed_at" -- "$RECEIPT"
  for key in \
    computer_use computer_use_evidence computer_use_evidence_sha256 computer_use_scenarios \
    computer_use_screenshots_manifest computer_use_screenshots_sha256 computer_use_contact_sheet \
    computer_use_contact_sheet_sha256 computer_use_scenario_screenshots_sha256 \
    computer_use_provenance_manifest computer_use_provenance_manifest_sha256 computer_use_at; do
    /usr/bin/plutil -insert "verification.$key" -string "" -- "$RECEIPT"
  done
}

start_provenance() {
  local scenario="$1"
  local display_count="$2"
  local output="$CAPTURE_ROOT/$scenario.plist"
  /usr/bin/plutil -create xml1 "$output"
  /usr/bin/plutil -insert schema_version -integer 4 -- "$output"
  /usr/bin/plutil -insert kind -string computer-use-window-capture -- "$output"
  /usr/bin/plutil -insert source_fingerprint -string "$fingerprint" -- "$output"
  /usr/bin/plutil -insert scenario -string "$scenario" -- "$output"
  /usr/bin/plutil -insert install_transaction_id -string "$transaction_id" -- "$output"
  /usr/bin/plutil -insert installed_at -string "$installed_at" -- "$output"
  /usr/bin/plutil -insert captured_at -string 2026-07-11T00:01:00Z -- "$output"
  /usr/bin/plutil -insert process_identifier -integer "$installed_pid" -- "$output"
  /usr/bin/plutil -insert process_start_time_us -integer "$installed_process_start" -- "$output"
  /usr/bin/plutil -insert process_executable -string "$installed_executable" -- "$output"
  /usr/bin/plutil -insert process_arguments_sha256 -string "$arguments_hash" -- "$output"
  /usr/bin/plutil -insert app_cdhash -string "$cdhash" -- "$output"
  /usr/bin/plutil -insert app_executable_sha256 -string "$executable_hash" -- "$output"
  /usr/bin/plutil -insert capture_root -string "$CAPTURE_ROOT" -- "$output"
  /usr/bin/plutil -insert available_display_count -integer "$display_count" -- "$output"
  /usr/bin/plutil -insert display_count -integer 0 -- "$output"
  /usr/bin/plutil -insert state_assertions -dictionary -- "$output"
  /usr/bin/plutil -insert state_assertions.values -dictionary -- "$output"
  case "$scenario" in
    launch)
      /usr/bin/plutil -insert state_assertions.values.main_window -string present -- "$output"
      ;;
    source_editor)
      /usr/bin/plutil -insert state_assertions.values.editor_focused -string true -- "$output"
      /usr/bin/plutil -insert state_assertions.values.editor_nonempty -string true -- "$output"
      ;;
    selection_hotkey)
      /usr/bin/plutil -insert state_assertions.values.mock_translation -string present -- "$output"
      /usr/bin/plutil -insert state_assertions.values.source_contains -string LexiRay -- "$output"
      /usr/bin/plutil -insert state_assertions.values.source_kind -string Accessibility -- "$output"
      ;;
    language_direction)
      /usr/bin/plutil -insert state_assertions.values.source_picker -string Japanese -- "$output"
      /usr/bin/plutil -insert state_assertions.values.target_picker -string English -- "$output"
      /usr/bin/plutil -insert state_assertions.values.mock_direction -string 'Direction: ja -> en' -- "$output"
      ;;
    speech_controls)
      /usr/bin/plutil -insert state_assertions.values.stop_control_count -string 1 -- "$output"
      /usr/bin/plutil -insert state_assertions.values.stop_control_identifier \
        -string FloatingPanelSourceSpeech -- "$output"
      ;;
    panel_visual_states)
      /usr/bin/plutil -insert state_assertions.values.app_active -string false -- "$output"
      /usr/bin/plutil -insert state_assertions.values.floating_layer -string 3 -- "$output"
      /usr/bin/plutil -insert state_assertions.values.pinned_control -string Unpin -- "$output"
      /usr/bin/plutil -insert state_assertions.values.resized -string true -- "$output"
      ;;
    ocr_result_display_1|ocr_result_display_2)
      local display_index=1
      [[ "$scenario" == ocr_result_display_2 ]] && display_index=2
      /usr/bin/plutil -insert state_assertions.values.capture_display_index -string "$display_index" -- "$output"
      /usr/bin/plutil -insert state_assertions.values.display_count -string "$display_count" -- "$output"
      /usr/bin/plutil -insert state_assertions.values.display_index -string "$display_index" -- "$output"
      /usr/bin/plutil -insert state_assertions.values.mock_translation -string present -- "$output"
      /usr/bin/plutil -insert state_assertions.values.source_contains -string LexiRay -- "$output"
      /usr/bin/plutil -insert state_assertions.values.source_kind -string OCR -- "$output"
      ;;
    ocr_multi_display)
      /usr/bin/plutil -insert state_assertions.values.overlay_count -string "$display_count" -- "$output"
      /usr/bin/plutil -insert state_assertions.values.display_count -string "$display_count" -- "$output"
      ;;
  esac
  /usr/bin/plutil -insert captures -array -- "$output"
}

add_capture() {
  local scenario="$1"
  local capture_index="$2"
  local window_identifier="$3"
  local window_name="$4"
  local window_layer="$5"
  local x="$6"
  local y="$7"
  local width="$8"
  local height="$9"
  local plist="$CAPTURE_ROOT/$scenario.plist"
  local png="$CAPTURE_ROOT/$scenario-window-$window_identifier.png"
  local window_role
  case "$scenario" in
    launch) window_role=main ;;
    ocr_multi_display) window_role=ocr-overlay ;;
    *) window_role=panel ;;
  esac
  cp "$EVIDENCE_DIR/fixture-$scenario.png" "$png"
  /usr/bin/plutil -insert "captures.$capture_index" -dictionary -- "$plist"
  /usr/bin/plutil -insert "captures.$capture_index.window_id" -integer "$window_identifier" -- "$plist"
  /usr/bin/plutil -insert "captures.$capture_index.window_name" -string "$window_name" -- "$plist"
  /usr/bin/plutil -insert "captures.$capture_index.window_role" -string "$window_role" -- "$plist"
  /usr/bin/plutil -insert "captures.$capture_index.window_layer" -integer "$window_layer" -- "$plist"
  /usr/bin/plutil -insert "captures.$capture_index.bounds" -dictionary -- "$plist"
  /usr/bin/plutil -insert "captures.$capture_index.bounds.x" -float "$x" -- "$plist"
  /usr/bin/plutil -insert "captures.$capture_index.bounds.y" -float "$y" -- "$plist"
  /usr/bin/plutil -insert "captures.$capture_index.bounds.width" -float "$width" -- "$plist"
  /usr/bin/plutil -insert "captures.$capture_index.bounds.height" -float "$height" -- "$plist"
  /usr/bin/plutil -insert "captures.$capture_index.png_path" -string "$png" -- "$plist"
  /usr/bin/plutil -insert "captures.$capture_index.png_sha256" -string "$(sha256_file "$png")" -- "$plist"
  /usr/bin/plutil -insert "captures.$capture_index.pixel_width" -integer 240 -- "$plist"
  /usr/bin/plutil -insert "captures.$capture_index.pixel_height" -integer 160 -- "$plist"
}

finish_provenance() {
  local scenario="$1"
  /usr/bin/plutil -convert json -r -o "$CAPTURE_ROOT/$scenario.json" -- "$CAPTURE_ROOT/$scenario.plist"
  rm -f "$CAPTURE_ROOT/$scenario.plist"
}

display_count="$(/usr/bin/swift "$ROOT_DIR/script/acceptance_evidence.swift" displays | wc -l | tr -d ' ')"
[[ "$display_count" -gt 0 ]]

start_provenance launch "$display_count"
add_capture launch 0 100 LexiRay 0 100 100 820 560
finish_provenance launch

window_identifier=101
for scenario in selection_hotkey source_editor language_direction speech_controls panel_visual_states; do
  start_provenance "$scenario" "$display_count"
  add_capture "$scenario" 0 "$window_identifier" "LexiRay Floating Panel" 3 200 200 420 300
  finish_provenance "$scenario"
  window_identifier=$((window_identifier + 1))
done

display_index=0
while IFS=$'\t' read -r x y width height; do
  if [[ "$display_index" -lt 2 ]]; then
    scenario="ocr_result_display_$((display_index + 1))"
    panel_x="$(awk -v value="$x" 'BEGIN { printf "%.0f", value + 100 }')"
    panel_y="$(awk -v value="$y" 'BEGIN { printf "%.0f", value + 100 }')"
    start_provenance "$scenario" "$display_count"
    add_capture "$scenario" 0 "$window_identifier" "LexiRay Floating Panel" 3 \
      "$panel_x" "$panel_y" 420 300
    finish_provenance "$scenario"
    window_identifier=$((window_identifier + 1))
  fi
  display_index=$((display_index + 1))
done < <(/usr/bin/swift "$ROOT_DIR/script/acceptance_evidence.swift" displays)
[[ "$display_index" -ge 2 ]]

start_provenance ocr_multi_display "$display_count"
/usr/bin/plutil -replace display_count -integer "$display_count" -- "$CAPTURE_ROOT/ocr_multi_display.plist"
capture_index=0
while IFS=$'\t' read -r x y width height; do
  add_capture ocr_multi_display "$capture_index" "$((200 + capture_index))" "" 1000 \
    "$x" "$y" "$width" "$height"
  capture_index=$((capture_index + 1))
done < <(/usr/bin/swift "$ROOT_DIR/script/acceptance_evidence.swift" displays)
[[ "$capture_index" -eq "$display_count" ]]
finish_provenance ocr_multi_display

make_receipt

rebuild_hash_manifests() {
  local scenario png index=0
  : >"$PROVENANCE_MANIFEST"
  : >"$SCREENSHOTS_MANIFEST"
  rm -rf "$INPUT_DIR"
  mkdir -p "$INPUT_DIR"
  for scenario in "${COMPUTER_USE_REQUIRED_SCENARIOS[@]}"; do
    printf '%s\t%s\t%s\n' \
      "$(sha256_file "$CAPTURE_ROOT/$scenario.json")" "$scenario" "$CAPTURE_ROOT/$scenario.json" \
      >>"$PROVENANCE_MANIFEST"
    for png in "$CAPTURE_ROOT/$scenario-window-"*.png; do
      [[ -f "$png" ]] || continue
      printf '%s  %s\n' "$(sha256_file "$png")" "$png" >>"$SCREENSHOTS_MANIFEST"
      index=$((index + 1))
      cp "$png" "$INPUT_DIR/$(printf '%02d' "$index")-$scenario-${png##*/}"
    done
  done
}

make_manifest() {
  local provenance_hash screenshots_hash contact_hash combined_hash screenshot_count
  provenance_hash="$(sha256_file "$PROVENANCE_MANIFEST")"
  screenshots_hash="$(sha256_file "$SCREENSHOTS_MANIFEST")"
  contact_hash="$(sha256_file "$CONTACT_SHEET")"
  screenshot_count="$(wc -l <"$SCREENSHOTS_MANIFEST" | tr -d ' ')"
  combined_hash="$(sha256_joined_values \
    "$(computer_use_matrix_csv)" "$provenance_hash" "$screenshots_hash" "$contact_hash")"
  /usr/bin/plutil -create xml1 "$MANIFEST"
  /usr/bin/plutil -insert schema_version -integer 4 -- "$MANIFEST"
  /usr/bin/plutil -insert kind -string computer-use -- "$MANIFEST"
  /usr/bin/plutil -insert status -string passed -- "$MANIFEST"
  /usr/bin/plutil -insert source_fingerprint -string "$fingerprint" -- "$MANIFEST"
  /usr/bin/plutil -insert installed_path -string /Applications/LexiRay.app -- "$MANIFEST"
  /usr/bin/plutil -insert installed_pid -string "$installed_pid" -- "$MANIFEST"
  /usr/bin/plutil -insert installed_process_start_time_us \
    -string "$installed_process_start" -- "$MANIFEST"
  /usr/bin/plutil -insert app_cdhash -string "$cdhash" -- "$MANIFEST"
  /usr/bin/plutil -insert app_executable_sha256 -string "$executable_hash" -- "$MANIFEST"
  /usr/bin/plutil -insert app_certificate_sha256 -string "$certificate_hash" -- "$MANIFEST"
  /usr/bin/plutil -insert app_designated_requirement_sha256 -string "$requirement_hash" -- "$MANIFEST"
  /usr/bin/plutil -insert app_entitlements_sha256 -string "$entitlements_hash" -- "$MANIFEST"
  /usr/bin/plutil -insert acceptance_root -string "$installed_root" -- "$MANIFEST"
  /usr/bin/plutil -insert defaults_suite -string "$installed_suite" -- "$MANIFEST"
  /usr/bin/plutil -insert install_transaction_id -string "$transaction_id" -- "$MANIFEST"
  /usr/bin/plutil -insert installed_at -string "$installed_at" -- "$MANIFEST"
  /usr/bin/plutil -insert scenarios -string "$(computer_use_matrix_csv)" -- "$MANIFEST"
  /usr/bin/plutil -insert scenario_count -integer "${#COMPUTER_USE_REQUIRED_SCENARIOS[@]}" -- "$MANIFEST"
  /usr/bin/plutil -insert scenario_provenance_manifest -string "$PROVENANCE_MANIFEST" -- "$MANIFEST"
  /usr/bin/plutil -insert scenario_provenance_manifest_sha256 -string "$provenance_hash" -- "$MANIFEST"
  /usr/bin/plutil -insert screenshots_manifest -string "$SCREENSHOTS_MANIFEST" -- "$MANIFEST"
  /usr/bin/plutil -insert screenshots_sha256 -string "$screenshots_hash" -- "$MANIFEST"
  /usr/bin/plutil -insert screenshot_count -integer "$screenshot_count" -- "$MANIFEST"
  /usr/bin/plutil -insert contact_sheet -string "$CONTACT_SHEET" -- "$MANIFEST"
  /usr/bin/plutil -insert contact_sheet_sha256 -string "$contact_hash" -- "$MANIFEST"
  /usr/bin/plutil -insert scenario_screenshots_sha256 -string "$combined_hash" -- "$MANIFEST"
  /usr/bin/plutil -insert created_at -string "$manifest_created_at" -- "$MANIFEST"
}

refresh_fixture() {
  rebuild_hash_manifests
  "$ROOT_DIR/script/make_contact_sheet.swift" "$INPUT_DIR" "$CONTACT_SHEET" >/dev/null
  make_manifest
}

bind_receipt_to_manifest() {
  /usr/bin/plutil -replace verification.computer_use -string passed -- "$RECEIPT"
  /usr/bin/plutil -replace verification.computer_use_evidence -string "$MANIFEST" -- "$RECEIPT"
  /usr/bin/plutil -replace verification.computer_use_evidence_sha256 \
    -string "$(sha256_file "$MANIFEST")" -- "$RECEIPT"
  /usr/bin/plutil -replace verification.computer_use_scenarios \
    -string "$(plist_value "$MANIFEST" scenarios)" -- "$RECEIPT"
  /usr/bin/plutil -replace verification.computer_use_screenshots_manifest \
    -string "$(plist_value "$MANIFEST" screenshots_manifest)" -- "$RECEIPT"
  /usr/bin/plutil -replace verification.computer_use_screenshots_sha256 \
    -string "$(plist_value "$MANIFEST" screenshots_sha256)" -- "$RECEIPT"
  /usr/bin/plutil -replace verification.computer_use_contact_sheet \
    -string "$(plist_value "$MANIFEST" contact_sheet)" -- "$RECEIPT"
  /usr/bin/plutil -replace verification.computer_use_contact_sheet_sha256 \
    -string "$(plist_value "$MANIFEST" contact_sheet_sha256)" -- "$RECEIPT"
  /usr/bin/plutil -replace verification.computer_use_scenario_screenshots_sha256 \
    -string "$(plist_value "$MANIFEST" scenario_screenshots_sha256)" -- "$RECEIPT"
  /usr/bin/plutil -replace verification.computer_use_provenance_manifest \
    -string "$(plist_value "$MANIFEST" scenario_provenance_manifest)" -- "$RECEIPT"
  /usr/bin/plutil -replace verification.computer_use_provenance_manifest_sha256 \
    -string "$(plist_value "$MANIFEST" scenario_provenance_manifest_sha256)" -- "$RECEIPT"
  /usr/bin/plutil -replace verification.computer_use_at -string 2026-07-11T00:03:00Z -- "$RECEIPT"
}

refresh_fixture
validate_computer_use_manifest "$RECEIPT" "$MANIFEST" 0
bind_receipt_to_manifest
computer_use_receipt_matches_manifest "$RECEIPT" "$MANIFEST"
/usr/bin/plutil -replace verification.computer_use_contact_sheet_sha256 \
  -string "$(printf '9%.0s' {1..64})" -- "$RECEIPT"
if computer_use_receipt_matches_manifest "$RECEIPT" "$MANIFEST" >/dev/null 2>&1; then
  echo "Computer Use handoff accepted receipt metadata that disagrees with its manifest" >&2
  exit 1
fi
bind_receipt_to_manifest

# A live manifest handoff verifies each sequential scenario from its sealed
# capture and checks the exact installed process once. It must not demand that
# every historical UI state still be live simultaneously.
eval "$(declare -f verify_computer_use_provenance |
  sed '1s/verify_computer_use_provenance/original_verify_computer_use_provenance/')"
eval "$(declare -f validate_installed_acceptance_process |
  sed '1s/validate_installed_acceptance_process/original_validate_installed_acceptance_process/')"
LIVE_FLAG_LOG="$EVIDENCE_DIR/live-flags.txt"
live_process_check_count=0
: >"$LIVE_FLAG_LOG"
verify_computer_use_provenance() {
  printf '%s\n' "$4" >>"$LIVE_FLAG_LOG"
  original_verify_computer_use_provenance "$1" "$2" "$3" 0 "$5" "$6"
}
validate_installed_acceptance_process() {
  live_process_check_count=$((live_process_check_count + 1))
  return 0
}
validate_computer_use_manifest "$RECEIPT" "$MANIFEST" 1
[[ "$(wc -l <"$LIVE_FLAG_LOG" | tr -d ' ')" == "${#COMPUTER_USE_REQUIRED_SCENARIOS[@]}" &&
  "$(sort -u "$LIVE_FLAG_LOG")" == 0 &&
  "$live_process_check_count" == 1 ]] || {
  echo "Live manifest validation re-checked a sequential scenario as current state" >&2
  exit 1
}
eval "$(declare -f original_verify_computer_use_provenance |
  sed '1s/original_verify_computer_use_provenance/verify_computer_use_provenance/')"
eval "$(declare -f original_validate_installed_acceptance_process |
  sed '1s/original_validate_installed_acceptance_process/validate_installed_acceptance_process/')"

# Every canonical state predicate is required independently; a scenario label
# plus a generic panel image cannot stand in for the live AX/window state.
while IFS='|' read -r scenario key invalid_value; do
  cp "$CAPTURE_ROOT/$scenario.json" "$EVIDENCE_DIR/state-backup.json"
  /usr/bin/plutil -replace "state_assertions.values.$key" -string "$invalid_value" \
    -- "$CAPTURE_ROOT/$scenario.json"
  if verify_computer_use_provenance \
    "$RECEIPT" "$CAPTURE_ROOT/$scenario.json" "$scenario" 0 0 >/dev/null 2>&1; then
    echo "Computer Use provenance accepted invalid $scenario state: $key=$invalid_value" >&2
    exit 1
  fi
  mv "$EVIDENCE_DIR/state-backup.json" "$CAPTURE_ROOT/$scenario.json"
done <<'STATE_CASES'
launch|main_window|missing
selection_hotkey|source_kind|Manual
source_editor|editor_focused|false
language_direction|mock_direction|Direction: en -> ja
speech_controls|stop_control_count|2
panel_visual_states|app_active|true
ocr_result_display_1|source_kind|Manual
ocr_result_display_2|source_kind|Accessibility
ocr_multi_display|overlay_count|0
STATE_CASES

# OCR result evidence must seal source_kind=OCR; omitting the field entirely
# cannot be replaced by a generic translated floating-panel capture.
cp "$CAPTURE_ROOT/ocr_result_display_1.json" "$EVIDENCE_DIR/ocr-source-kind-backup.json"
/usr/bin/plutil -remove state_assertions.values.source_kind \
  -- "$CAPTURE_ROOT/ocr_result_display_1.json"
if verify_computer_use_provenance \
  "$RECEIPT" "$CAPTURE_ROOT/ocr_result_display_1.json" \
  ocr_result_display_1 0 0 >/dev/null 2>&1; then
  echo "Computer Use provenance accepted OCR result evidence without source_kind=OCR" >&2
  exit 1
fi
mv "$EVIDENCE_DIR/ocr-source-kind-backup.json" "$CAPTURE_ROOT/ocr_result_display_1.json"

# Moving a display-1 OCR result panel onto display 2 must not manufacture
# display-2 capture provenance. The live panel geometry may match display 2,
# but its sealed OCR source remains display 1 and must be rejected.
cp "$CAPTURE_ROOT/ocr_result_display_2.json" "$EVIDENCE_DIR/ocr-capture-display-backup.json"
/usr/bin/plutil -replace state_assertions.values.capture_display_index -string 1 \
  -- "$CAPTURE_ROOT/ocr_result_display_2.json"
if verify_computer_use_provenance \
  "$RECEIPT" "$CAPTURE_ROOT/ocr_result_display_2.json" \
  ocr_result_display_2 0 0 >/dev/null 2>&1; then
  echo "Computer Use provenance accepted a display-1 OCR result moved onto display 2" >&2
  exit 1
fi
mv "$EVIDENCE_DIR/ocr-capture-display-backup.json" "$CAPTURE_ROOT/ocr_result_display_2.json"

# Evidence from the same source but a different installation transaction must
# never be replayed, even if every app hash and PID-shaped field still matches.
replacement_transaction="22222222-2222-4222-8222-222222222222"
/usr/bin/plutil -replace verification.install_transaction_id -string "$replacement_transaction" -- "$RECEIPT"
if validate_computer_use_manifest "$RECEIPT" "$MANIFEST" 0 >/dev/null 2>&1; then
  echo "Computer Use manifest accepted evidence from an older install transaction" >&2
  exit 1
fi
/usr/bin/plutil -replace verification.install_transaction_id -string "$transaction_id" -- "$RECEIPT"

# PID-shaped provenance is insufficient: the kernel process start time must
# match the process that mark-installed bound into the receipt.
cp "$CAPTURE_ROOT/launch.json" "$EVIDENCE_DIR/process-start-backup.json"
/usr/bin/plutil -replace process_start_time_us -integer "$((installed_process_start + 1))" \
  -- "$CAPTURE_ROOT/launch.json"
rebuild_hash_manifests
make_manifest
if validate_computer_use_manifest "$RECEIPT" "$MANIFEST" 0 >/dev/null 2>&1; then
  echo "Computer Use manifest accepted a reused PID with a different process start time" >&2
  exit 1
fi
mv "$EVIDENCE_DIR/process-start-backup.json" "$CAPTURE_ROOT/launch.json"
refresh_fixture

# Capture provenance must postdate the installation it claims to verify.
cp "$CAPTURE_ROOT/launch.json" "$EVIDENCE_DIR/captured-at-backup.json"
/usr/bin/plutil -replace captured_at -string 2026-07-10T23:59:59Z -- "$CAPTURE_ROOT/launch.json"
rebuild_hash_manifests
make_manifest
if validate_computer_use_manifest "$RECEIPT" "$MANIFEST" 0 >/dev/null 2>&1; then
  echo "Computer Use manifest accepted capture evidence predating installation" >&2
  exit 1
fi
mv "$EVIDENCE_DIR/captured-at-backup.json" "$CAPTURE_ROOT/launch.json"
refresh_fixture

# Captures must not postdate manifest creation, and neither manifest nor
# capture timestamps may claim evidence from the future.
cp "$CAPTURE_ROOT/launch.json" "$EVIDENCE_DIR/captured-at-backup.json"
/usr/bin/plutil -replace captured_at -string 2026-07-11T00:03:00Z -- "$CAPTURE_ROOT/launch.json"
rebuild_hash_manifests
make_manifest
if validate_computer_use_manifest "$RECEIPT" "$MANIFEST" 0 >/dev/null 2>&1; then
  echo "Computer Use manifest accepted capture evidence created after the manifest" >&2
  exit 1
fi
manifest_created_at="2099-01-01T00:02:00Z"
/usr/bin/plutil -replace captured_at -string 2099-01-01T00:01:00Z -- "$CAPTURE_ROOT/launch.json"
rebuild_hash_manifests
make_manifest
if validate_computer_use_manifest "$RECEIPT" "$MANIFEST" 0 >/dev/null 2>&1; then
  echo "Computer Use manifest accepted future-dated evidence" >&2
  exit 1
fi
manifest_created_at="2026-07-11T00:02:00Z"
mv "$EVIDENCE_DIR/captured-at-backup.json" "$CAPTURE_ROOT/launch.json"
refresh_fixture

# Arbitrary or incomplete scenario claims cannot replace the canonical matrix.
/usr/bin/plutil -replace scenarios -string foo -- "$MANIFEST"
if validate_computer_use_manifest "$RECEIPT" "$MANIFEST" 0 >/dev/null 2>&1; then
  echo "Computer Use manifest accepted an arbitrary scenario" >&2
  exit 1
fi
make_manifest
/usr/bin/plutil -replace scenarios -string launch,source_editor -- "$MANIFEST"
/usr/bin/plutil -replace scenario_count -integer 2 -- "$MANIFEST"
if validate_computer_use_manifest "$RECEIPT" "$MANIFEST" 0 >/dev/null 2>&1; then
  echo "Computer Use manifest accepted an incomplete matrix" >&2
  exit 1
fi
make_manifest

# A separately rehashed PNG cannot replace the contact sheet derived from the
# exact sealed scenario screenshots.
cp "$CONTACT_SHEET" "$EVIDENCE_DIR/contact-sheet-backup.png"
cp "$EVIDENCE_DIR/fixture-launch.png" "$CONTACT_SHEET"
make_manifest
if validate_computer_use_manifest "$RECEIPT" "$MANIFEST" 0 >/dev/null 2>&1; then
  echo "Computer Use manifest accepted an unrelated rehashed contact sheet" >&2
  exit 1
fi
mv "$EVIDENCE_DIR/contact-sheet-backup.png" "$CONTACT_SHEET"
make_manifest

# Rehashing non-image bytes cannot turn them into PID-owned PNG evidence.
launch_png="$CAPTURE_ROOT/launch-window-100.png"
cp "$launch_png" "$EVIDENCE_DIR/launch-backup.png"
printf 'not-a-png\n' >"$launch_png"
/usr/bin/plutil -replace captures.0.png_sha256 -string "$(sha256_file "$launch_png")" \
  -- "$CAPTURE_ROOT/launch.json"
rebuild_hash_manifests
make_manifest
if validate_computer_use_manifest "$RECEIPT" "$MANIFEST" 0 >/dev/null 2>&1; then
  echo "Computer Use manifest accepted rehashed text as a PNG" >&2
  exit 1
fi
mv "$EVIDENCE_DIR/launch-backup.png" "$launch_png"
/usr/bin/plutil -replace captures.0.png_sha256 -string "$(sha256_file "$launch_png")" \
  -- "$CAPTURE_ROOT/launch.json"
refresh_fixture

# A dashboard/main-window capture cannot impersonate a floating-panel scenario.
/usr/bin/plutil -replace captures.0.window_role -string main \
  -- "$CAPTURE_ROOT/source_editor.json"
rebuild_hash_manifests
make_manifest
if validate_computer_use_manifest "$RECEIPT" "$MANIFEST" 0 >/dev/null 2>&1; then
  echo "Computer Use manifest accepted the wrong window semantics for source_editor" >&2
  exit 1
fi

rg -F 'displays >= 2' "$ROOT_DIR/script/acceptance_evidence.swift" >/dev/null || {
  echo "Computer Use evidence does not reject single-display multi-display claims" >&2
  exit 1
}
rg -F 'CGPreflightScreenCaptureAccess()' "$ROOT_DIR/script/acceptance_evidence.swift" >/dev/null || {
  echo "Computer Use evidence does not fail fast without Screen Recording" >&2
  exit 1
}
if rg -n 'CGRequestScreenCaptureAccess[[:space:]]*\(' \
  "$ROOT_DIR/script/acceptance_evidence.swift" >/dev/null; then
  echo "Computer Use evidence must not trigger a Screen Recording prompt" >&2
  exit 1
fi

echo "COMPUTER_USE_MANIFEST_TEST_PASS"

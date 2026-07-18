#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACCEPTANCE_DIR="${LEXIRAY_ACCEPTANCE_DIR:-$ROOT_DIR/build/acceptance}"
EVIDENCE_HELPER="$ROOT_DIR/script/acceptance_evidence.swift"
GUI_ARTIFACT_ROOT="$ROOT_DIR/build/ui-artifacts"
# shellcheck source=release_identity.sh
source "$ROOT_DIR/script/release_identity.sh"

# Only app, build, test, and verification inputs participate. Documentation-only
# edits do not make an otherwise identical app candidate stale.
SOURCE_PATHS=(
  LexiRay
  LexiRayTests
  Package.swift
  project.yml
  .swiftformat
  .github/workflows
  script
)

COMPUTER_USE_SCENARIO_CATALOG=(
  launch
  login_item_settings
  selection_hotkey
  source_editor
  language_direction
  speech_controls
  panel_visual_states
  ocr_result_display_1
  ocr_result_display_2
  ocr_multi_display
)
COMPUTER_USE_REQUIRED_SCENARIOS=("${COMPUTER_USE_SCENARIO_CATALOG[@]}")

usage() {
  cat >&2 <<'EOF'
usage: script/acceptance_receipt.sh <command> [arguments]

commands:
  fingerprint
  path
  l3-path
  l3-valid
  record-l3 <xcresult-bundle>
  validate-gui-artifact <app> <artifact-dir> <contact-sheet>
  write-candidate <app> <passed|not-required> [artifact-dir] [contact-sheet]
  require-automated-candidate
  require-candidate
  field <keypath>
  mark-gui-inspected <passed|failed> [evidence]
  mark-installed <app> <acceptance-pid> <transaction-id>
  mark-login-item-probe <passed|failed|blocked> <manifest>
  require-login-item-probe
  installed-transaction-valid <transaction-id> <app>
  verify-app-match <app>
  app-identity <app>
  computer-use-matrix
  capture-computer-use <scenario> [window-id]
  write-computer-use-manifest
  mark-computer-use <passed|failed|blocked> <manifest-or-evidence>
  require-handoff
EOF
  exit 2
}

sha256_file() {
  /usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{print $1}'
}

valid_computer_use_scenario() {
  local expected
  for expected in "${COMPUTER_USE_SCENARIO_CATALOG[@]}"; do
    [[ "$1" == "$expected" ]] && return 0
  done
  return 1
}

set_computer_use_required_scenarios() {
  local csv="$1"
  local scenario requested_index=0
  local -a requested selected
  IFS=',' read -r -a requested <<<"$csv"
  [[ ${#requested[@]} -gt 0 && "${requested[0]}" == launch ]] || {
    echo "Computer Use matrix must start with launch." >&2
    return 1
  }
  for scenario in "${COMPUTER_USE_SCENARIO_CATALOG[@]}"; do
    if [[ $requested_index -lt ${#requested[@]} &&
      "${requested[$requested_index]}" == "$scenario" ]]; then
      selected+=("$scenario")
      requested_index=$((requested_index + 1))
    fi
  done
  [[ $requested_index -eq ${#requested[@]} ]] || {
    echo "Computer Use matrix has an unknown, duplicate, or out-of-order scenario: $csv" >&2
    return 1
  }
  COMPUTER_USE_REQUIRED_SCENARIOS=("${selected[@]}")
}

load_computer_use_required_scenarios() {
  local receipt="$1"
  set_computer_use_required_scenarios \
    "$(plist_value "$receipt" verification.computer_use_required_scenarios)"
}

computer_use_catalog_csv() {
  printf '%s\n' "${COMPUTER_USE_SCENARIO_CATALOG[@]}" | paste -sd, -
}

source_fingerprint() {
  local manifest all_paths present_paths hashes path mode digest fingerprint
  manifest="$(mktemp "${TMPDIR:-/tmp}/lexiray-source-manifest.XXXXXX")"
  all_paths="$(mktemp "${TMPDIR:-/tmp}/lexiray-source-paths.XXXXXX")"
  present_paths="$(mktemp "${TMPDIR:-/tmp}/lexiray-source-present.XXXXXX")"
  hashes="$(mktemp "${TMPDIR:-/tmp}/lexiray-source-hashes.XXXXXX")"

  cd "$ROOT_DIR"
  git ls-files --cached --others --exclude-standard -- "${SOURCE_PATHS[@]}" |
    LC_ALL=C sort -u >"$all_paths"
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    if [[ -e "$path" || -L "$path" ]]; then
      printf '%s\n' "$path" >>"$present_paths"
    else
      printf 'deleted\t-\t-\t%s\n' "$path" >>"$manifest"
    fi
  done <"$all_paths"

  git hash-object --no-filters --stdin-paths <"$present_paths" >"$hashes"
  exec 3<"$hashes"
  while IFS= read -r path; do
    IFS= read -r digest <&3
    if [[ -L "$path" ]]; then
      mode=symlink
    elif [[ -x "$path" ]]; then
      mode=executable
    else
      mode=regular
    fi
    printf 'present\t%s\t%s\t%s\n' "$mode" "$digest" "$path" >>"$manifest"
  done <"$present_paths"
  exec 3<&-

  fingerprint="$(sha256_file "$manifest")"
  rm -f "$manifest" "$all_paths" "$present_paths" "$hashes"
  printf '%s\n' "$fingerprint"
}

receipt_path() {
  printf '%s/candidate-%s.json\n' "$ACCEPTANCE_DIR" "$(source_fingerprint)"
}

l3_path() {
  printf '%s/l3-%s.json\n' "$ACCEPTANCE_DIR" "$(source_fingerprint)"
}

plist_value() {
  local receipt="$1"
  local keypath="$2"
  /usr/bin/plutil -extract "$keypath" raw -n -- "$receipt" 2>/dev/null
}

validate_plist() {
  # On current macOS, `plutil -lint` accepts XML/binary plists but rejects
  # valid JSON produced by `plutil -convert json`. Converting to /dev/null
  # parses every supported plist representation without rewriting evidence.
  /usr/bin/plutil -convert xml1 -o /dev/null -- "$1" >/dev/null 2>&1
}

signature_details() {
  /usr/bin/codesign -dvvv "$1" 2>&1
}

app_authority() {
  signature_details "$1" | /usr/bin/awk -F= '
    /^Authority=/ && !found {
      print substr($0, index($0, "=") + 1)
      found = 1
    }
  '
}

app_cdhash() {
  signature_details "$1" | /usr/bin/awk -F= '
    /^CDHash=/ && !found {
      print $2
      found = 1
    }
  '
}

app_version() {
  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$1/Contents/Info.plist"
}

app_build() {
  /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$1/Contents/Info.plist"
}

app_bundle_id() {
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$1/Contents/Info.plist"
}

app_executable_sha256() {
  sha256_file "$1/Contents/MacOS/LexiRay"
}

app_certificate_sha256() {
  lexiray_app_certificate_sha256 "$1"
}

app_designated_requirement() {
  lexiray_app_designated_requirement "$1"
}

app_designated_requirement_sha256() {
  lexiray_app_designated_requirement_sha256 "$1"
}

app_entitlements_sha256() {
  lexiray_app_entitlements_sha256 "$1"
}

verify_app() {
  local app="$1"
  [[ -d "$app" ]] || {
    echo "Acceptance app is missing: $app" >&2
    return 1
  }
  /usr/bin/codesign --verify --deep --strict "$app" >/dev/null 2>&1 || {
    echo "Acceptance app has an invalid signature: $app" >&2
    return 1
  }
  [[ -n "$(app_authority "$app")" ]] || {
    echo "Acceptance app is ad hoc or unsigned: $app" >&2
    return 1
  }
  [[ "$(app_bundle_id "$app")" == "io.github.tensornull.lexiray" ]] || {
    echo "Acceptance app has the wrong bundle identifier: $app" >&2
    return 1
  }
  [[ "$(app_certificate_sha256 "$app" 2>/dev/null || true)" =~ ^[0-9a-fA-F]{64}$ ]] || {
    echo "Acceptance app has no extractable leaf signing certificate: $app" >&2
    return 1
  }
  [[ -n "$(app_designated_requirement "$app" 2>/dev/null || true)" ]] || {
    echo "Acceptance app has no designated requirement: $app" >&2
    return 1
  }
  [[ "$(app_entitlements_sha256 "$app" 2>/dev/null || true)" =~ ^[0-9a-fA-F]{64}$ ]] || {
    echo "Acceptance app entitlements cannot be verified: $app" >&2
    return 1
  }
}

write_app_identity() {
  [[ $# -eq 1 ]] || usage
  local app="$1"
  local plist json
  verify_app "$app"
  plist="$(mktemp "${TMPDIR:-/tmp}/lexiray-app-identity-plist.XXXXXX")"
  json="$(mktemp "${TMPDIR:-/tmp}/lexiray-app-identity-json.XXXXXX")"
  /usr/bin/plutil -create xml1 "$plist"
  /usr/bin/plutil -insert cdhash -string "$(app_cdhash "$app")" -- "$plist"
  /usr/bin/plutil -insert executable_sha256 -string "$(app_executable_sha256 "$app")" -- "$plist"
  /usr/bin/plutil -insert certificate_sha256 -string "$(app_certificate_sha256 "$app")" -- "$plist"
  /usr/bin/plutil -insert designated_requirement -string "$(app_designated_requirement "$app")" -- "$plist"
  /usr/bin/plutil -insert designated_requirement_sha256 -string "$(app_designated_requirement_sha256 "$app")" -- "$plist"
  /usr/bin/plutil -insert entitlements_sha256 -string "$(app_entitlements_sha256 "$app")" -- "$plist"
  /usr/bin/plutil -convert json -r -o "$json" -- "$plist"
  /bin/cat "$json"
  /bin/rm -f "$plist" "$json"
}

plist_insert_string() {
  /usr/bin/plutil -insert "$2" -string "$3" -- "$1"
}

require_gui_artifact_directory() {
  [[ $# -eq 1 ]] || return 1
  local artifact_dir="$1"
  local relative component current canonical
  local -a components=()

  case "$artifact_dir" in
    "$GUI_ARTIFACT_ROOT"/*) ;;
    *)
      echo "GUI artifact directory must be below $GUI_ARTIFACT_ROOT." >&2
      return 1
      ;;
  esac
  relative="${artifact_dir#"$GUI_ARTIFACT_ROOT"/}"
  [[ -n "$relative" && "$relative" != /* && "$relative" != */ &&
    "$relative" != *//* && "$relative" != *$'\n'* ]] || {
    echo "GUI artifact directory has a non-canonical path." >&2
    return 1
  }

  for current in "$ROOT_DIR" "$ROOT_DIR/build" "$GUI_ARTIFACT_ROOT"; do
    [[ -d "$current" && ! -L "$current" ]] || {
      echo "GUI artifact root contains a missing, non-directory, or symlink component: $current" >&2
      return 1
    }
    canonical="$(cd "$current" && pwd -P)" || return 1
    [[ "$canonical" == "$current" ]] || {
      echo "GUI artifact root is not canonical: $current" >&2
      return 1
    }
  done

  current="$GUI_ARTIFACT_ROOT"
  IFS='/' read -r -a components <<<"$relative"
  for component in "${components[@]}"; do
    [[ -n "$component" && "$component" != . && "$component" != .. ]] || {
      echo "GUI artifact directory has an unsafe path component." >&2
      return 1
    }
    current="$current/$component"
    [[ -d "$current" && ! -L "$current" ]] || {
      echo "GUI artifact directory contains a missing, non-directory, or symlink component: $current" >&2
      return 1
    }
  done
  canonical="$(cd "$artifact_dir" && pwd -P)" || return 1
  [[ "$canonical" == "$artifact_dir" ]] || {
    echo "GUI artifact directory escaped its canonical root." >&2
    return 1
  }
}

require_gui_artifact_file() {
  [[ $# -eq 1 ]] || return 1
  local evidence="$1"
  local parent basename

  case "$evidence" in
    "$GUI_ARTIFACT_ROOT"/*) ;;
    *)
      echo "GUI evidence must live below $GUI_ARTIFACT_ROOT." >&2
      return 1
      ;;
  esac
  parent="${evidence%/*}"
  basename="${evidence##*/}"
  [[ -n "$basename" && "$basename" != . && "$basename" != .. &&
    "$basename" != *$'\n'* ]] || {
    echo "GUI evidence has an unsafe file name." >&2
    return 1
  }
  require_gui_artifact_directory "$parent" || return 1
  [[ -f "$evidence" && ! -L "$evidence" && -s "$evidence" ]] || {
    echo "GUI evidence must be a non-empty regular file, not a symlink: $evidence" >&2
    return 1
  }
}

require_candidate_gui_evidence_paths() {
  [[ $# -eq 5 ]] || return 1
  local artifact_dir="$1"
  local contact_sheet="$2"
  local results_file="$3"
  local gui_manifest="$4"
  local screenshots_manifest="$5"

  require_gui_artifact_directory "$artifact_dir" || return 1
  [[ "$contact_sheet" == "$artifact_dir/contact-sheet.png" &&
    "$results_file" == "$artifact_dir/results.txt" &&
    "$gui_manifest" == "$artifact_dir/gui-run.json" &&
    "$screenshots_manifest" == "$artifact_dir/gui-screenshots.sha256" ]] || {
    echo "Candidate GUI evidence files must use their canonical run paths." >&2
    return 1
  }
  require_gui_artifact_file "$contact_sheet" || return 1
  require_gui_artifact_file "$results_file" || return 1
  require_gui_artifact_file "$gui_manifest" || return 1
  require_gui_artifact_file "$screenshots_manifest" || return 1
  /usr/bin/swift "$EVIDENCE_HELPER" png "$contact_sheet" >/dev/null || {
    echo "Candidate GUI contact sheet is not a valid PNG." >&2
    return 1
  }
}

validate_gui_scenario_set() {
  [[ $# -eq 2 ]] || return 1
  local scenarios_csv="$1"
  local context="$2"

  if ! GUI_SCENARIO_CSV="$scenarios_csv" /usr/bin/awk '
    BEGIN {
      csv = ENVIRON["GUI_SCENARIO_CSV"]
      if (csv == "" || index(csv, "\n") > 0 ||
          csv ~ /^,/ || csv ~ /,$/ || csv ~ /,,/) {
        invalid = 1
      }
      actual_count = split(csv, actual, ",")
      for (i = 1; i <= actual_count; i++) {
        name = actual[i]
        if (name == "" || actual_seen[name]++) {
          invalid = 1
        }
      }
    }
    {
      name = $0
      if (name == "" || expected[name]++) {
        invalid = 1
      }
      expected_count++
    }
    END {
      if (expected_count == 0 || actual_count != expected_count) {
        invalid = 1
      }
      for (i = 1; i <= actual_count; i++) {
        if (!(actual[i] in expected)) {
          invalid = 1
        }
      }
      for (name in expected) {
        if (!(name in actual_seen)) {
          invalid = 1
        }
      }
      exit invalid ? 1 : 0
    }
  ' < <("$ROOT_DIR/script/ui/run.sh" --list); then
    echo "$context scenario manifest is not the exact canonical GUI scenario set." >&2
    return 1
  fi
}

validate_gui_results() {
  [[ $# -eq 2 ]] || return 1
  local results_file="$1"
  local context="$2"

  if ! /usr/bin/awk '
    FNR == NR {
      name = $0
      if (name == "" || expected[name]++) {
        invalid = 1
      }
      expected_count++
      next
    }
    {
      if (substr($0, 1, 6) != "PASS  ") {
        invalid = 1
      }
      name = substr($0, 7)
      if (name == "" || !(name in expected) || passed[name]++) {
        invalid = 1
      }
      result_count++
    }
    END {
      if (expected_count == 0 || result_count != expected_count) {
        invalid = 1
      }
      for (name in expected) {
        if (!(name in passed)) {
          invalid = 1
        }
      }
      exit invalid ? 1 : 0
    }
  ' - "$results_file" < <("$ROOT_DIR/script/ui/run.sh" --list); then
    echo "$context results do not contain exactly one PASS for every canonical GUI scenario." >&2
    return 1
  fi
}

validate_gui_scenario_evidence() {
  [[ $# -eq 3 ]] || return 1
  validate_gui_scenario_set "$1" "$3" || return 1
  validate_gui_results "$2" "$3"
}

validate_gui_artifact() {
  [[ $# -eq 3 ]] || usage
  local app="$1"
  local artifact_dir="$2"
  local contact_sheet="$3"
  local fingerprint results_file gui_manifest screenshots_manifest screenshot_count
  local manifest_scenarios results_hash screenshots_manifest_hash contact_sheet_hash
  local rebuilt_contact_sheet

  fingerprint="$(source_fingerprint)"
  results_file="$artifact_dir/results.txt"
  gui_manifest="$artifact_dir/gui-run.json"
  screenshots_manifest="$artifact_dir/gui-screenshots.sha256"
  require_candidate_gui_evidence_paths \
    "$artifact_dir" "$contact_sheet" "$results_file" "$gui_manifest" \
    "$screenshots_manifest" || {
    echo "Reusable GUI artifact has unsafe or incomplete evidence paths." >&2
    return 1
  }
  verify_app "$app"
  [[ -f "$app.source-fingerprint" && "$(<"$app.source-fingerprint")" == "$fingerprint" ]] || {
    echo "Reusable GUI artifact app is not attested for the current source." >&2
    return 1
  }
  validate_plist "$gui_manifest" || {
    echo "Reusable GUI run manifest is malformed." >&2
    return 1
  }
  manifest_scenarios="$(plist_value "$gui_manifest" scenarios)"
  validate_gui_scenario_evidence \
    "$manifest_scenarios" "$results_file" "Reusable GUI" || return 1
  results_hash="$(sha256_file "$results_file")"
  screenshots_manifest_hash="$(plist_value "$gui_manifest" screenshots_manifest_sha256)"
  screenshot_count="$(plist_value "$gui_manifest" screenshot_count)"
  contact_sheet_hash="$(sha256_file "$contact_sheet")"
  [[ "$screenshot_count" =~ ^[1-9][0-9]*$ &&
    "$(plist_value "$gui_manifest" screenshots_manifest)" == "$screenshots_manifest" &&
    "$(sha256_file "$screenshots_manifest")" == "$screenshots_manifest_hash" ]] || {
    echo "Reusable GUI screenshot evidence is missing or stale." >&2
    return 1
  }
  verify_screenshot_manifest "$screenshots_manifest" "$screenshot_count" "$artifact_dir" || {
    echo "Reusable GUI raw screenshots do not match their manifest." >&2
    return 1
  }
  rebuilt_contact_sheet="$(mktemp "${TMPDIR:-/tmp}/lexiray-gui-contact-sheet.XXXXXX")"
  if ! rebuild_gui_contact_sheet \
    "$screenshots_manifest" "$artifact_dir" "$rebuilt_contact_sheet" ||
    [[ "$(sha256_file "$rebuilt_contact_sheet")" != "$contact_sheet_hash" ]] ||
    ! cmp -s "$rebuilt_contact_sheet" "$contact_sheet"; then
    rm -f "$rebuilt_contact_sheet"
    echo "Reusable GUI contact sheet is not derived from its sealed raw screenshots." >&2
    return 1
  fi
  rm -f "$rebuilt_contact_sheet"
  [[ "$(plist_value "$gui_manifest" kind)" == gui-run &&
    "$(plist_value "$gui_manifest" source_fingerprint)" == "$fingerprint" &&
    "$(plist_value "$gui_manifest" app_path)" == "$app" &&
    "$(plist_value "$gui_manifest" app_cdhash)" == "$(app_cdhash "$app")" &&
    "$(plist_value "$gui_manifest" app_executable_sha256)" == "$(app_executable_sha256 "$app")" &&
    "$(plist_value "$gui_manifest" app_certificate_sha256)" == "$(app_certificate_sha256 "$app")" &&
    "$(plist_value "$gui_manifest" app_designated_requirement_sha256)" == \
      "$(app_designated_requirement_sha256 "$app")" &&
    "$(plist_value "$gui_manifest" app_entitlements_sha256)" == "$(app_entitlements_sha256 "$app")" &&
    "$(plist_value "$gui_manifest" scenarios)" == "$manifest_scenarios" &&
    "$(plist_value "$gui_manifest" results_sha256)" == "$results_hash" &&
    "$(plist_value "$gui_manifest" screenshots_manifest)" == "$screenshots_manifest" &&
    "$(plist_value "$gui_manifest" screenshots_manifest_sha256)" == "$screenshots_manifest_hash" &&
    "$(plist_value "$gui_manifest" screenshot_count)" == "$screenshot_count" &&
    "$(source_fingerprint)" == "$fingerprint" ]] || {
    echo "Reusable GUI artifact is not bound to the current source and app." >&2
    return 1
  }
}

write_candidate() {
  [[ $# -ge 2 && $# -le 4 ]] || usage
  local app="$1"
  local gui_status="$2"
  local artifact_dir="${3:-}"
  local contact_sheet="${4:-}"
  local fingerprint_before fingerprint_after receipt tmp_plist tmp_json
  local authority cdhash version build bundle_id executable_hash certificate_hash
  local designated_requirement designated_requirement_hash entitlements_hash
  local git_head git_branch created_at scenario_names manifest_scenarios screenshot_count results_hash contact_sheet_hash
  local results_file gui_manifest gui_manifest_hash gui_screenshots_manifest gui_screenshots_manifest_hash
  local rebuilt_contact_sheet
  local login_item_probe_status
  local computer_use_required_scenarios

  case "$gui_status" in
    passed|not-required) ;;
    *) echo "GUI status must be passed or not-required." >&2; exit 2 ;;
  esac
  case "${LEXIRAY_LOGIN_ITEM_PROBE_REQUIRED:-0}" in
    0) login_item_probe_status=not-required ;;
    1) login_item_probe_status=pending ;;
    *) echo "LEXIRAY_LOGIN_ITEM_PROBE_REQUIRED must be 0 or 1." >&2; exit 2 ;;
  esac
  set_computer_use_required_scenarios \
    "${LEXIRAY_COMPUTER_USE_REQUIRED_SCENARIOS:-$(computer_use_catalog_csv)}" || exit 2
  computer_use_required_scenarios="$(computer_use_matrix_csv)"

  fingerprint_before="$(source_fingerprint)"
  l3_valid >/dev/null || {
    echo "Current source has no reusable L3 evidence; run ./script/verify.sh pr first." >&2
    exit 1
  }
  "$ROOT_DIR/script/context_lint.sh" >/dev/null
  verify_app "$app"
  [[ -f "$app.source-fingerprint" && "$(<"$app.source-fingerprint")" == "$fingerprint_before" ]] || {
    echo "Candidate app has no current-source build attestation; rebuild it with build_and_run.sh." >&2
    exit 1
  }
  authority="$(app_authority "$app")"
  cdhash="$(app_cdhash "$app")"
  version="$(app_version "$app")"
  build="$(app_build "$app")"
  bundle_id="$(app_bundle_id "$app")"
  executable_hash="$(app_executable_sha256 "$app")"
  certificate_hash="$(app_certificate_sha256 "$app")"
  designated_requirement="$(app_designated_requirement "$app")"
  designated_requirement_hash="$(app_designated_requirement_sha256 "$app")"
  entitlements_hash="$(app_entitlements_sha256 "$app")"
  git_head="$(git -C "$ROOT_DIR" rev-parse HEAD)"
  git_branch="$(git -C "$ROOT_DIR" symbolic-ref --quiet --short HEAD || printf 'detached')"
  created_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  scenario_names=""
  screenshot_count=0
  results_hash=""
  contact_sheet_hash=""
  gui_manifest=""
  gui_manifest_hash=""
  gui_screenshots_manifest=""
  gui_screenshots_manifest_hash=""
  if [[ "$gui_status" == "passed" ]]; then
    scenario_names="$("$ROOT_DIR/script/ui/run.sh" --list | paste -sd, -)"
    results_file="$artifact_dir/results.txt"
    gui_manifest="$artifact_dir/gui-run.json"
    gui_screenshots_manifest="$artifact_dir/gui-screenshots.sha256"
    require_candidate_gui_evidence_paths \
      "$artifact_dir" "$contact_sheet" "$results_file" "$gui_manifest" \
      "$gui_screenshots_manifest" || {
      echo "GUI artifact bundle has unsafe or incomplete evidence paths." >&2
      exit 1
    }
    results_hash="$(sha256_file "$results_file")"
    contact_sheet_hash="$(sha256_file "$contact_sheet")"
    validate_plist "$gui_manifest" || {
      echo "GUI run manifest is malformed." >&2
      exit 1
    }
    manifest_scenarios="$(plist_value "$gui_manifest" scenarios)"
    validate_gui_scenario_evidence \
      "$manifest_scenarios" "$results_file" "GUI artifact" || exit 1
    gui_screenshots_manifest_hash="$(plist_value "$gui_manifest" screenshots_manifest_sha256)"
    screenshot_count="$(plist_value "$gui_manifest" screenshot_count)"
    [[ "$screenshot_count" =~ ^[1-9][0-9]*$ &&
      "$(plist_value "$gui_manifest" screenshots_manifest)" == "$gui_screenshots_manifest" &&
      "$(sha256_file "$gui_screenshots_manifest")" == "$gui_screenshots_manifest_hash" ]] || {
      echo "GUI screenshots/contact sheet are missing or stale." >&2
      exit 1
    }
    verify_screenshot_manifest "$gui_screenshots_manifest" "$screenshot_count" "$artifact_dir" || {
      echo "GUI raw screenshots do not match their manifest." >&2
      exit 1
    }
    rebuilt_contact_sheet="$(mktemp "${TMPDIR:-/tmp}/lexiray-gui-contact-sheet.XXXXXX")"
    if ! rebuild_gui_contact_sheet \
      "$gui_screenshots_manifest" "$artifact_dir" "$rebuilt_contact_sheet" ||
      [[ "$(sha256_file "$rebuilt_contact_sheet")" != "$contact_sheet_hash" ]] ||
      ! cmp -s "$rebuilt_contact_sheet" "$contact_sheet"; then
      rm -f "$rebuilt_contact_sheet"
      echo "GUI contact sheet is not derived from the sealed raw screenshots." >&2
      exit 1
    fi
    rm -f "$rebuilt_contact_sheet"
    [[ "$(plist_value "$gui_manifest" kind)" == gui-run &&
      "$(plist_value "$gui_manifest" source_fingerprint)" == "$fingerprint_before" &&
      "$(plist_value "$gui_manifest" app_path)" == "$app" &&
      "$(plist_value "$gui_manifest" app_cdhash)" == "$cdhash" &&
      "$(plist_value "$gui_manifest" app_executable_sha256)" == "$executable_hash" &&
      "$(plist_value "$gui_manifest" app_certificate_sha256)" == "$certificate_hash" &&
      "$(plist_value "$gui_manifest" app_designated_requirement_sha256)" == "$designated_requirement_hash" &&
      "$(plist_value "$gui_manifest" app_entitlements_sha256)" == "$entitlements_hash" &&
      "$(plist_value "$gui_manifest" scenarios)" == "$manifest_scenarios" &&
      "$(plist_value "$gui_manifest" results_sha256)" == "$results_hash" &&
      "$(plist_value "$gui_manifest" screenshots_manifest)" == "$gui_screenshots_manifest" &&
      "$(plist_value "$gui_manifest" screenshots_manifest_sha256)" == "$gui_screenshots_manifest_hash" &&
      "$(plist_value "$gui_manifest" screenshot_count)" == "$screenshot_count" ]] || {
      echo "GUI run manifest does not match the current source and candidate app." >&2
      exit 1
    }
    gui_manifest_hash="$(sha256_file "$gui_manifest")"
  fi

  mkdir -p "$ACCEPTANCE_DIR"
  receipt="$ACCEPTANCE_DIR/candidate-$fingerprint_before.json"
  tmp_plist="$(mktemp "$ACCEPTANCE_DIR/.candidate-plist.XXXXXX")"
  tmp_json="$(mktemp "$ACCEPTANCE_DIR/.candidate-json.XXXXXX")"

  /usr/bin/plutil -create xml1 "$tmp_plist"
  /usr/bin/plutil -insert schema_version -integer 3 -- "$tmp_plist"
  plist_insert_string "$tmp_plist" kind candidate
  plist_insert_string "$tmp_plist" source_fingerprint "$fingerprint_before"
  plist_insert_string "$tmp_plist" git_head "$git_head"
  plist_insert_string "$tmp_plist" git_branch "$git_branch"
  plist_insert_string "$tmp_plist" created_at "$created_at"
  plist_insert_string "$tmp_plist" version "$version"
  plist_insert_string "$tmp_plist" build "$build"

  /usr/bin/plutil -insert app -dictionary -- "$tmp_plist"
  plist_insert_string "$tmp_plist" app.path "$app"
  plist_insert_string "$tmp_plist" app.bundle_id "$bundle_id"
  plist_insert_string "$tmp_plist" app.authority "$authority"
  plist_insert_string "$tmp_plist" app.cdhash "$cdhash"
  plist_insert_string "$tmp_plist" app.executable_sha256 "$executable_hash"
  plist_insert_string "$tmp_plist" app.certificate_sha256 "$certificate_hash"
  plist_insert_string "$tmp_plist" app.designated_requirement "$designated_requirement"
  plist_insert_string "$tmp_plist" app.designated_requirement_sha256 "$designated_requirement_hash"
  plist_insert_string "$tmp_plist" app.entitlements_sha256 "$entitlements_hash"
  plist_insert_string "$tmp_plist" app.source_fingerprint "$fingerprint_before"

  /usr/bin/plutil -insert verification -dictionary -- "$tmp_plist"
  plist_insert_string "$tmp_plist" verification.context_lint passed
  plist_insert_string "$tmp_plist" verification.l3 passed
  plist_insert_string "$tmp_plist" verification.l3_fingerprint "$fingerprint_before"
  plist_insert_string "$tmp_plist" verification.unit_tests full-suite
  plist_insert_string "$tmp_plist" verification.workspace_build passed
  plist_insert_string "$tmp_plist" verification.gui "$gui_status"
  plist_insert_string "$tmp_plist" verification.gui_scenarios "$scenario_names"
  plist_insert_string "$tmp_plist" verification.gui_artifact_dir "$artifact_dir"
  plist_insert_string "$tmp_plist" verification.contact_sheet "$contact_sheet"
  plist_insert_string "$tmp_plist" verification.gui_manifest "$gui_manifest"
  plist_insert_string "$tmp_plist" verification.gui_manifest_sha256 "$gui_manifest_hash"
  plist_insert_string "$tmp_plist" verification.gui_results_sha256 "$results_hash"
  plist_insert_string "$tmp_plist" verification.gui_screenshots_manifest "$gui_screenshots_manifest"
  plist_insert_string "$tmp_plist" verification.gui_screenshots_manifest_sha256 "$gui_screenshots_manifest_hash"
  plist_insert_string "$tmp_plist" verification.contact_sheet_sha256 "$contact_sheet_hash"
  /usr/bin/plutil -insert verification.screenshot_count -integer "$screenshot_count" -- "$tmp_plist"
  if [[ "$gui_status" == passed ]]; then
    plist_insert_string "$tmp_plist" verification.gui_visual_inspection pending
  else
    plist_insert_string "$tmp_plist" verification.gui_visual_inspection not-required
  fi
  plist_insert_string "$tmp_plist" verification.gui_visual_inspection_evidence ""
  plist_insert_string "$tmp_plist" verification.gui_visual_inspection_at ""
  plist_insert_string "$tmp_plist" verification.login_item_system_probe "$login_item_probe_status"
  plist_insert_string "$tmp_plist" verification.login_item_system_probe_manifest ""
  plist_insert_string "$tmp_plist" verification.login_item_system_probe_manifest_sha256 ""
  plist_insert_string "$tmp_plist" verification.login_item_system_probe_at ""
  plist_insert_string "$tmp_plist" verification.installed pending
  plist_insert_string "$tmp_plist" verification.installed_path ""
  plist_insert_string "$tmp_plist" verification.installed_cdhash ""
  plist_insert_string "$tmp_plist" verification.installed_certificate_sha256 ""
  plist_insert_string "$tmp_plist" verification.installed_designated_requirement_sha256 ""
  plist_insert_string "$tmp_plist" verification.installed_entitlements_sha256 ""
  plist_insert_string "$tmp_plist" verification.installed_pid ""
  plist_insert_string "$tmp_plist" verification.installed_process_start_time_us ""
  plist_insert_string "$tmp_plist" verification.installed_acceptance_root ""
  plist_insert_string "$tmp_plist" verification.installed_defaults_suite ""
  plist_insert_string "$tmp_plist" verification.install_transaction_id ""
  plist_insert_string "$tmp_plist" verification.installed_at ""
  plist_insert_string "$tmp_plist" verification.computer_use_required_scenarios \
    "$computer_use_required_scenarios"
  plist_insert_string "$tmp_plist" verification.computer_use pending
  plist_insert_string "$tmp_plist" verification.computer_use_evidence ""
  plist_insert_string "$tmp_plist" verification.computer_use_evidence_sha256 ""
  plist_insert_string "$tmp_plist" verification.computer_use_scenarios ""
  plist_insert_string "$tmp_plist" verification.computer_use_screenshots_manifest ""
  plist_insert_string "$tmp_plist" verification.computer_use_screenshots_sha256 ""
  plist_insert_string "$tmp_plist" verification.computer_use_contact_sheet ""
  plist_insert_string "$tmp_plist" verification.computer_use_contact_sheet_sha256 ""
  plist_insert_string "$tmp_plist" verification.computer_use_scenario_screenshots_sha256 ""
  plist_insert_string "$tmp_plist" verification.computer_use_provenance_manifest ""
  plist_insert_string "$tmp_plist" verification.computer_use_provenance_manifest_sha256 ""
  plist_insert_string "$tmp_plist" verification.computer_use_at ""

  fingerprint_after="$(source_fingerprint)"
  if [[ "$fingerprint_after" != "$fingerprint_before" ]]; then
    echo "Source inputs changed while writing the candidate receipt; rerun candidate verification." >&2
    exit 1
  fi

  /usr/bin/plutil -convert json -r -o "$tmp_json" -- "$tmp_plist"
  validate_plist "$tmp_json"
  mv -f "$tmp_json" "$receipt"
  rm -f "$tmp_plist"
  chmod 600 "$receipt"
  printf '%s\n' "$receipt"
}

l3_valid() {
  local fingerprint receipt
  fingerprint="$(source_fingerprint)"
  receipt="$ACCEPTANCE_DIR/l3-$fingerprint.json"
  [[ -f "$receipt" ]] || return 1
  validate_plist "$receipt" || return 1
  [[ "$(plist_value "$receipt" kind)" == l3 &&
    "$(plist_value "$receipt" source_fingerprint)" == "$fingerprint" &&
    "$(plist_value "$receipt" result)" == passed ]] || return 1
  printf '%s\n' "$receipt"
}

record_l3() {
  [[ $# -eq 1 ]] || usage
  local result_bundle="$1"
  local fingerprint receipt tmp_plist tmp_json expected_bundle summary result passed failed total
  fingerprint="$(source_fingerprint)"
  expected_bundle="$ACCEPTANCE_DIR/l3-$fingerprint.xcresult"
  [[ "$result_bundle" == "$expected_bundle" && -d "$result_bundle" ]] || {
    echo "L3 result bundle must be the current fingerprint bundle: $expected_bundle" >&2
    return 1
  }
  summary="$(mktemp "${TMPDIR:-/tmp}/lexiray-l3-summary-json.XXXXXX")"
  xcrun xcresulttool get test-results summary --path "$result_bundle" --format json >"$summary"
  result="$(/usr/bin/plutil -extract result raw -n -- "$summary")"
  passed="$(/usr/bin/plutil -extract passedTests raw -n -- "$summary")"
  failed="$(/usr/bin/plutil -extract failedTests raw -n -- "$summary")"
  total="$(/usr/bin/plutil -extract totalTestCount raw -n -- "$summary")"
  rm -f "$summary"
  [[ "$result" == Passed && "$failed" == 0 && "$passed" -gt 0 && "$total" -gt 0 ]] || {
    echo "L3 xcresult is not a successful non-empty test run (result=$result passed=$passed failed=$failed total=$total)." >&2
    return 1
  }
  "$ROOT_DIR/script/context_lint.sh" >/dev/null
  swiftformat LexiRay LexiRayTests Package.swift --lint >/dev/null
  mkdir -p "$ACCEPTANCE_DIR"
  receipt="$ACCEPTANCE_DIR/l3-$fingerprint.json"
  tmp_plist="$(mktemp "$ACCEPTANCE_DIR/.l3-plist.XXXXXX")"
  tmp_json="$(mktemp "$ACCEPTANCE_DIR/.l3-json.XXXXXX")"
  /usr/bin/plutil -create xml1 "$tmp_plist"
  /usr/bin/plutil -insert schema_version -integer 1 -- "$tmp_plist"
  plist_insert_string "$tmp_plist" kind l3
  plist_insert_string "$tmp_plist" source_fingerprint "$fingerprint"
  plist_insert_string "$tmp_plist" git_head "$(git -C "$ROOT_DIR" rev-parse HEAD)"
  plist_insert_string "$tmp_plist" created_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  plist_insert_string "$tmp_plist" result passed
  plist_insert_string "$tmp_plist" result_bundle "$result_bundle"
  /usr/bin/plutil -insert passed_tests -integer "$passed" -- "$tmp_plist"
  /usr/bin/plutil -insert total_tests -integer "$total" -- "$tmp_plist"
  /usr/bin/plutil -convert json -r -o "$tmp_json" -- "$tmp_plist"
  validate_plist "$tmp_json"
  mv -f "$tmp_json" "$receipt"
  rm -f "$tmp_plist"
  chmod 600 "$receipt"
  printf '%s\n' "$receipt"
}

app_matches_receipt() {
  local receipt="$1"
  local app="$2"
  verify_app "$app"
  [[ "$(app_version "$app")" == "$(plist_value "$receipt" version)" &&
    "$(app_build "$app")" == "$(plist_value "$receipt" build)" &&
    "$(app_bundle_id "$app")" == "$(plist_value "$receipt" app.bundle_id)" &&
    "$(app_authority "$app")" == "$(plist_value "$receipt" app.authority)" &&
    "$(app_cdhash "$app")" == "$(plist_value "$receipt" app.cdhash)" &&
    "$(app_executable_sha256 "$app")" == "$(plist_value "$receipt" app.executable_sha256)" &&
    "$(app_certificate_sha256 "$app")" == "$(plist_value "$receipt" app.certificate_sha256)" &&
    "$(app_designated_requirement "$app")" == "$(plist_value "$receipt" app.designated_requirement)" &&
    "$(app_designated_requirement_sha256 "$app")" == "$(plist_value "$receipt" app.designated_requirement_sha256)" &&
    "$(app_entitlements_sha256 "$app")" == "$(plist_value "$receipt" app.entitlements_sha256)" ]]
}

require_candidate() {
  local require_visual_inspection="${1:-1}"
  local fingerprint receipt recorded app
  fingerprint="$(source_fingerprint)"
  receipt="$ACCEPTANCE_DIR/candidate-$fingerprint.json"
  [[ -f "$receipt" ]] || {
    echo "No candidate acceptance receipt for source fingerprint $fingerprint." >&2
    echo "Run ./script/verify.sh candidate first." >&2
    return 1
  }
  l3_valid >/dev/null || {
    echo "Current source no longer has valid L3 evidence." >&2
    return 1
  }
  validate_plist "$receipt" || {
    echo "Candidate receipt is malformed: $receipt" >&2
    return 1
  }
  [[ "$(plist_value "$receipt" kind)" == candidate ]] || {
    echo "Acceptance receipt has the wrong kind: $receipt" >&2
    return 1
  }
  [[ "$(plist_value "$receipt" schema_version)" == 3 ]] || {
    echo "Candidate receipt schema is stale; rerun candidate verification." >&2
    return 1
  }
  recorded="$(plist_value "$receipt" source_fingerprint)"
  [[ "$recorded" == "$fingerprint" ]] || {
    echo "Candidate receipt source fingerprint is stale." >&2
    return 1
  }
  load_computer_use_required_scenarios "$receipt" || {
    echo "Candidate receipt has an invalid frozen Computer Use matrix." >&2
    return 1
  }
  local key expected
  for key in verification.context_lint verification.l3 verification.workspace_build; do
    expected="$(plist_value "$receipt" "$key")"
    [[ "$expected" == passed ]] || {
      echo "Candidate receipt does not record $key=passed." >&2
      return 1
    }
  done
  case "$(plist_value "$receipt" verification.gui)" in
    passed)
      local artifact_dir contact_sheet screenshot_count results_file gui_manifest gui_screenshots_manifest
      local manifest_scenarios
      local rebuilt_contact_sheet
      artifact_dir="$(plist_value "$receipt" verification.gui_artifact_dir)"
      contact_sheet="$(plist_value "$receipt" verification.contact_sheet)"
      screenshot_count="$(plist_value "$receipt" verification.screenshot_count)"
      results_file="$artifact_dir/results.txt"
      gui_manifest="$(plist_value "$receipt" verification.gui_manifest)"
      gui_screenshots_manifest="$(plist_value "$receipt" verification.gui_screenshots_manifest)"
      require_candidate_gui_evidence_paths \
        "$artifact_dir" "$contact_sheet" "$results_file" "$gui_manifest" \
        "$gui_screenshots_manifest" || {
        echo "Candidate GUI evidence has unsafe or incomplete paths." >&2
        return 1
      }
      [[ "$screenshot_count" =~ ^[1-9][0-9]*$ ]] || {
        echo "Candidate GUI evidence is missing or incomplete." >&2
        return 1
      }
      validate_plist "$gui_manifest" || {
        echo "Candidate GUI manifest is malformed." >&2
        return 1
      }
      manifest_scenarios="$(plist_value "$gui_manifest" scenarios)"
      validate_gui_scenario_evidence \
        "$manifest_scenarios" "$results_file" "Candidate GUI" || return 1
      validate_gui_scenario_set \
        "$(plist_value "$receipt" verification.gui_scenarios)" \
        "Candidate receipt GUI" || return 1
      [[ "$(sha256_file "$results_file")" == "$(plist_value "$receipt" verification.gui_results_sha256)" &&
        "$(sha256_file "$contact_sheet")" == "$(plist_value "$receipt" verification.contact_sheet_sha256)" &&
        "$(sha256_file "$gui_manifest")" == "$(plist_value "$receipt" verification.gui_manifest_sha256)" &&
        "$gui_screenshots_manifest" == "$artifact_dir/gui-screenshots.sha256" &&
        "$(sha256_file "$gui_screenshots_manifest")" == "$(plist_value "$receipt" verification.gui_screenshots_manifest_sha256)" ]] || {
        echo "Candidate GUI evidence no longer matches its receipt." >&2
        return 1
      }
      verify_screenshot_manifest "$gui_screenshots_manifest" "$screenshot_count" "$artifact_dir" || {
        echo "Candidate GUI raw screenshots no longer match their manifest." >&2
        return 1
      }
      rebuilt_contact_sheet="$(mktemp "${TMPDIR:-/tmp}/lexiray-gui-contact-sheet.XXXXXX")"
      if ! rebuild_gui_contact_sheet \
        "$gui_screenshots_manifest" "$artifact_dir" "$rebuilt_contact_sheet" ||
        [[ "$(sha256_file "$rebuilt_contact_sheet")" != \
          "$(plist_value "$receipt" verification.contact_sheet_sha256)" ]] ||
        ! cmp -s "$rebuilt_contact_sheet" "$contact_sheet"; then
        rm -f "$rebuilt_contact_sheet"
        echo "Candidate GUI contact sheet is not derived from its sealed raw screenshots." >&2
        return 1
      fi
      rm -f "$rebuilt_contact_sheet"
      [[ "$(plist_value "$gui_manifest" kind)" == gui-run &&
        "$(plist_value "$gui_manifest" source_fingerprint)" == "$fingerprint" &&
        "$(plist_value "$gui_manifest" app_cdhash)" == "$(plist_value "$receipt" app.cdhash)" &&
        "$(plist_value "$gui_manifest" app_executable_sha256)" == "$(plist_value "$receipt" app.executable_sha256)" &&
        "$(plist_value "$gui_manifest" app_certificate_sha256)" == "$(plist_value "$receipt" app.certificate_sha256)" &&
        "$(plist_value "$gui_manifest" app_designated_requirement_sha256)" == "$(plist_value "$receipt" app.designated_requirement_sha256)" &&
        "$(plist_value "$gui_manifest" app_entitlements_sha256)" == "$(plist_value "$receipt" app.entitlements_sha256)" &&
        "$(plist_value "$gui_manifest" scenarios)" == "$manifest_scenarios" &&
        "$(plist_value "$gui_manifest" results_sha256)" == "$(plist_value "$receipt" verification.gui_results_sha256)" &&
        "$(plist_value "$gui_manifest" screenshots_manifest)" == "$gui_screenshots_manifest" &&
        "$(plist_value "$gui_manifest" screenshots_manifest_sha256)" == "$(plist_value "$receipt" verification.gui_screenshots_manifest_sha256)" &&
        "$(plist_value "$gui_manifest" screenshot_count)" == "$screenshot_count" ]] || {
        echo "Candidate GUI manifest is not bound to this source and app." >&2
        return 1
      }
      if [[ "$require_visual_inspection" == 1 &&
        "$(plist_value "$receipt" verification.gui_visual_inspection)" != passed ]]; then
        echo "Candidate GUI contact sheet has not been visually inspected." >&2
        return 1
      fi
      ;;
    not-required) ;;
    *) echo "Candidate receipt does not have a completed GUI result." >&2; return 1 ;;
  esac

  app="$(plist_value "$receipt" app.path)"
  verify_app "$app"
  [[ -f "$app.source-fingerprint" &&
    "$(<"$app.source-fingerprint")" == "$fingerprint" &&
    "$(plist_value "$receipt" app.source_fingerprint)" == "$fingerprint" ]] || {
    echo "Candidate app build attestation is missing or stale." >&2
    return 1
  }
  [[ "$(app_version "$app")" == "$(plist_value "$receipt" version)" &&
    "$(app_build "$app")" == "$(plist_value "$receipt" build)" &&
    "$(app_bundle_id "$app")" == "$(plist_value "$receipt" app.bundle_id)" &&
    "$(app_authority "$app")" == "$(plist_value "$receipt" app.authority)" &&
    "$(app_cdhash "$app")" == "$(plist_value "$receipt" app.cdhash)" &&
    "$(app_executable_sha256 "$app")" == "$(plist_value "$receipt" app.executable_sha256)" &&
    "$(app_certificate_sha256 "$app")" == "$(plist_value "$receipt" app.certificate_sha256)" &&
    "$(app_designated_requirement "$app")" == "$(plist_value "$receipt" app.designated_requirement)" &&
    "$(app_designated_requirement_sha256 "$app")" == "$(plist_value "$receipt" app.designated_requirement_sha256)" &&
    "$(app_entitlements_sha256 "$app")" == "$(plist_value "$receipt" app.entitlements_sha256)" ]] || {
    echo "Candidate app metadata no longer matches its acceptance receipt." >&2
    return 1
  }

  if [[ "$(plist_value "$receipt" verification.installed)" == passed ]]; then
    local installed_path installed_cdhash install_transaction_id
    installed_path="$(plist_value "$receipt" verification.installed_path)"
    installed_cdhash="$(plist_value "$receipt" verification.installed_cdhash)"
    install_transaction_id="$(plist_value "$receipt" verification.install_transaction_id)"
    [[ "$installed_path" == /Applications/LexiRay.app &&
      "$installed_cdhash" == "$(plist_value "$receipt" app.cdhash)" &&
      "$(plist_value "$receipt" verification.installed_process_start_time_us)" =~ ^[1-9][0-9]*$ ]] &&
      valid_install_transaction_id "$install_transaction_id" || {
      echo "Candidate receipt does not identify the canonical installed app." >&2
      return 1
    }
    app_matches_receipt "$receipt" "$installed_path" || {
      echo "The installed app no longer matches the accepted candidate." >&2
      return 1
    }
  fi

  if [[ "$(plist_value "$receipt" verification.computer_use)" == passed ]]; then
    local computer_evidence computer_evidence_hash
    computer_evidence="$(plist_value "$receipt" verification.computer_use_evidence)"
    computer_evidence_hash="$(plist_value "$receipt" verification.computer_use_evidence_sha256)"
    require_evidence_file "$computer_evidence" || return 1
    [[ "$(sha256_file "$computer_evidence")" == "$computer_evidence_hash" ]] || {
      echo "Computer Use evidence no longer matches its receipt." >&2
      return 1
    }
    validate_computer_use_manifest "$receipt" "$computer_evidence" 0 || return 1
    computer_use_receipt_matches_manifest "$receipt" "$computer_evidence" || return 1
  fi
  printf '%s\n' "$receipt"
}

mark_login_item_probe() {
  [[ $# -eq 2 ]] || usage
  local status="$1"
  local manifest="$2"
  local receipt outcome completed_at app
  case "$status" in
    passed|failed|blocked) ;;
    *) echo "Login Item probe status must be passed, failed, or blocked." >&2; return 2 ;;
  esac
  receipt="$(require_candidate 1)"
  require_evidence_file "$manifest" || return 1
  validate_plist "$manifest" || { echo "Login Item probe manifest is malformed." >&2; return 1; }
  outcome="$(plist_value "$manifest" outcome)"
  completed_at="$(plist_value "$manifest" completed_at)"
  app="$(plist_value "$receipt" app.path)"
  [[ "$outcome" == "$status" &&
    "$(plist_value "$manifest" schema_version)" == 1 &&
    "$(plist_value "$manifest" kind)" == login-item-system-probe &&
    "$(plist_value "$manifest" source_fingerprint)" == "$(plist_value "$receipt" source_fingerprint)" &&
    "$(plist_value "$manifest" app_path)" == /Applications/LexiRay.app &&
    "$(plist_value "$manifest" bundle_id)" == "$(plist_value "$receipt" app.bundle_id)" &&
    "$(plist_value "$manifest" app_cdhash)" == "$(plist_value "$receipt" app.cdhash)" &&
    "$(plist_value "$manifest" app_executable_sha256)" == "$(plist_value "$receipt" app.executable_sha256)" &&
    "$(plist_value "$manifest" app_certificate_sha256)" == "$(plist_value "$receipt" app.certificate_sha256)" &&
    "$(plist_value "$manifest" app_designated_requirement_sha256)" == "$(plist_value "$receipt" app.designated_requirement_sha256)" ]] || {
    echo "Login Item probe manifest is not bound to the current candidate." >&2
    return 1
  }
  valid_utc_timestamp "$completed_at" || {
    echo "Login Item probe completion time is invalid." >&2
    return 1
  }
  utc_timestamp_not_future "$completed_at" || {
    echo "Login Item probe completion time is in the future." >&2
    return 1
  }
  if [[ "$status" == passed || "$status" == blocked ]]; then
    local initial_status registered_status final_status transition
    initial_status="$(plist_value "$manifest" initial_status)"
    registered_status="$(plist_value "$manifest" registered_status || true)"
    final_status="$(plist_value "$manifest" final_status)"
    transition="$initial_status:$registered_status:$final_status"
    case "$status:$transition" in
      passed:enabled::enabled | \
        passed:notRegistered:enabled:notRegistered | \
        passed:notRegistered:enabled:notFound | \
        passed:notFound:enabled:notRegistered | \
        passed:notFound:enabled:notFound | \
        blocked:requiresApproval::requiresApproval | \
        blocked:notRegistered:requiresApproval:notRegistered | \
        blocked:notRegistered:requiresApproval:notFound | \
        blocked:notFound:requiresApproval:notRegistered | \
        blocked:notFound:requiresApproval:notFound) ;;
      *)
        echo "Login Item probe outcome does not match a real reversible state transition." >&2
        return 1
        ;;
    esac
  fi
  app_matches_receipt "$receipt" /Applications/LexiRay.app || {
    echo "Login Item probe did not run against the current installed candidate." >&2
    return 1
  }
  update_receipt "$receipt" \
    verification.login_item_system_probe "$status" \
    verification.login_item_system_probe_manifest "$manifest" \
    verification.login_item_system_probe_manifest_sha256 "$(sha256_file "$manifest")" \
    verification.login_item_system_probe_at "$completed_at"
  printf '%s\n' "$receipt"
}

require_login_item_probe() {
  [[ $# -eq 0 ]] || usage
  local receipt manifest
  receipt="$(require_candidate 1)"
  [[ "$(plist_value "$receipt" verification.login_item_system_probe)" == passed ]] || {
    echo "Current candidate has no passing real Login Item system probe." >&2
    return 1
  }
  manifest="$(plist_value "$receipt" verification.login_item_system_probe_manifest)"
  require_evidence_file "$manifest" || return 1
  [[ "$(sha256_file "$manifest")" == \
    "$(plist_value "$receipt" verification.login_item_system_probe_manifest_sha256)" ]] || {
    echo "Login Item probe evidence no longer matches its receipt." >&2
    return 1
  }
  printf '%s\n' "$receipt"
}

mark_gui_inspected() {
  [[ $# -ge 1 && $# -le 2 ]] || usage
  local status="$1"
  local evidence="${2:-}"
  local receipt gui_status
  case "$status" in
    passed|failed) ;;
    *) echo "GUI inspection status must be passed or failed." >&2; exit 2 ;;
  esac
  receipt="$(require_candidate 0)"
  gui_status="$(plist_value "$receipt" verification.gui)"
  [[ "$gui_status" == passed ]] || {
    echo "GUI visual inspection is not required for this candidate." >&2
    return 1
  }
  if [[ "$status" == passed ]]; then
    require_gui_artifact_file "$evidence"
    [[ "$evidence" == "$(plist_value "$receipt" verification.contact_sheet)" ]] || {
      echo "GUI inspection evidence must be the candidate contact sheet." >&2
      return 1
    }
  elif [[ -z "$evidence" ]]; then
    echo "GUI inspection failure evidence is required." >&2
    return 1
  fi
  update_receipt "$receipt" \
    verification.gui_visual_inspection "$status" \
    verification.gui_visual_inspection_evidence "$evidence" \
    verification.gui_visual_inspection_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf '%s\n' "$receipt"
}

update_receipt() {
  local receipt="$1"
  shift
  local tmp_plist tmp_json key value
  tmp_plist="$(mktemp "$ACCEPTANCE_DIR/.update-plist.XXXXXX")"
  tmp_json="$(mktemp "$ACCEPTANCE_DIR/.update-json.XXXXXX")"
  /usr/bin/plutil -convert xml1 -o "$tmp_plist" -- "$receipt"
  while [[ $# -gt 0 ]]; do
    key="$1"
    value="$2"
    shift 2
    /usr/bin/plutil -replace "$key" -string "$value" -- "$tmp_plist"
  done
  /usr/bin/plutil -convert json -r -o "$tmp_json" -- "$tmp_plist"
  validate_plist "$tmp_json"
  mv -f "$tmp_json" "$receipt"
  rm -f "$tmp_plist"
  chmod 600 "$receipt"
}

validate_sole_lexiray_process() {
  local expected_pid="$1"
  local observed_pid observed_count=0
  while IFS= read -r observed_pid; do
    [[ -n "$observed_pid" ]] || continue
    observed_count=$((observed_count + 1))
    [[ "$observed_pid" == "$expected_pid" ]] || return 1
  done < <(pgrep -x LexiRay 2>/dev/null || true)
  [[ "$observed_count" -eq 1 ]] || return 1
}

validate_installed_acceptance_process() {
  local installed="$1"
  local pid="$2"
  local acceptance_root="$3"
  local defaults_suite="$4"
  local expected_start_time="${5:-}"
  local -a expected_arguments=(
    --lexiray-acceptance-profile
    --lexiray-acceptance-workspace-root "$ROOT_DIR"
    --lexiray-acceptance-root "$acceptance_root"
    --lexiray-acceptance-defaults-suite "$defaults_suite"
    --lexiray-acceptance-login-item-status notFound
  )
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  [[ -f "$EVIDENCE_HELPER" ]] || return 1
  validate_sole_lexiray_process "$pid" || return 1
  if [[ -n "$expected_start_time" ]]; then
    [[ "$expected_start_time" =~ ^[1-9][0-9]*$ ]] || return 1
    /usr/bin/swift "$EVIDENCE_HELPER" process \
      "$pid" "$installed/Contents/MacOS/LexiRay" "$expected_start_time" -- \
      "${expected_arguments[@]}" >/dev/null
  else
    /usr/bin/swift "$EVIDENCE_HELPER" process \
      "$pid" "$installed/Contents/MacOS/LexiRay" -- "${expected_arguments[@]}" >/dev/null
  fi
}

installed_acceptance_process_start_time() {
  local installed="$1"
  local pid="$2"
  local acceptance_root="$3"
  local defaults_suite="$4"
  local -a expected_arguments=(
    --lexiray-acceptance-profile
    --lexiray-acceptance-workspace-root "$ROOT_DIR"
    --lexiray-acceptance-root "$acceptance_root"
    --lexiray-acceptance-defaults-suite "$defaults_suite"
    --lexiray-acceptance-login-item-status notFound
  )
  /usr/bin/swift "$EVIDENCE_HELPER" process-identity \
    "$pid" "$installed/Contents/MacOS/LexiRay" -- "${expected_arguments[@]}"
}

capture_installed_launch() {
  [[ $# -eq 10 ]] || return 2
  local installed="$1"
  local pid="$2"
  local process_start_time="$3"
  local acceptance_root="$4"
  local defaults_suite="$5"
  local fingerprint="$6"
  local transaction_id="$7"
  local installed_at="$8"
  local cdhash="$9"
  local executable_hash="${10}"
  local capture_root="$ACCEPTANCE_DIR/computer-use-captures-$fingerprint-$transaction_id"
  local provenance
  local -a expected_arguments=(
    --lexiray-acceptance-profile
    --lexiray-acceptance-workspace-root "$ROOT_DIR"
    --lexiray-acceptance-root "$acceptance_root"
    --lexiray-acceptance-defaults-suite "$defaults_suite"
    --lexiray-acceptance-login-item-status notFound
  )

  case "$capture_root" in
    "$ROOT_DIR"/build/acceptance/*) ;;
    *) echo "Install-time launch capture root escaped build/acceptance." >&2; return 1 ;;
  esac
  [[ ! -e "$capture_root" && ! -L "$capture_root" ]] || {
    echo "Install-time launch capture root already exists." >&2
    return 1
  }
  mkdir -p "$capture_root"
  if ! provenance="$(/usr/bin/swift "$EVIDENCE_HELPER" capture \
    "$pid" "$installed/Contents/MacOS/LexiRay" launch "$capture_root" \
    "$fingerprint" "$cdhash" "$executable_hash" "$transaction_id" \
    "$installed_at" "$process_start_time" -- "${expected_arguments[@]}")"; then
    rm -rf -- "$capture_root"
    echo "Installed app did not present a capturable main window during installation." >&2
    return 1
  fi
  [[ "$provenance" == "$capture_root/launch.json" &&
    -f "$provenance" && ! -L "$provenance" && -s "$provenance" ]] || {
    rm -rf -- "$capture_root"
    echo "Install-time launch evidence was not written to its canonical path." >&2
    return 1
  }
  printf '%s\n' "$provenance"
}

valid_install_transaction_id() {
  [[ "$1" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$ ]]
}

installed_acceptance_root_path() {
  local fingerprint="$1"
  local transaction_id="$2"
  [[ "$fingerprint" =~ ^[0-9a-f]{64}$ ]] || return 1
  valid_install_transaction_id "$transaction_id" || return 1
  printf '%s/build/acceptance-data/installed-%s-%s\n' \
    "$ROOT_DIR" "$fingerprint" "$transaction_id"
}

installed_acceptance_defaults_suite() {
  local fingerprint="$1"
  local transaction_id="$2"
  [[ "$fingerprint" =~ ^[0-9a-f]{64}$ ]] || return 1
  valid_install_transaction_id "$transaction_id" || return 1
  printf 'io.github.tensornull.lexiray.acceptance.installed.%s.%s\n' \
    "${fingerprint:0:16}" "${transaction_id//-/}"
}

mark_installed() {
  [[ $# -eq 3 ]] || usage
  local installed="$1"
  local pid="$2"
  local transaction_id="$3"
  local receipt fingerprint acceptance_root defaults_suite process_start_time
  local installed_at launch_provenance
  local expected_cdhash expected_version expected_build expected_authority expected_executable
  local expected_certificate expected_requirement expected_entitlements
  valid_install_transaction_id "$transaction_id" || {
    echo "Install transaction ID must be a lowercase RFC 4122 UUID." >&2
    return 1
  }
  receipt="$(require_candidate 1)"
  [[ "$installed" == /Applications/LexiRay.app ]] || {
    echo "Only /Applications/LexiRay.app can be recorded as installed." >&2
    return 1
  }
  verify_app "$installed"
  fingerprint="$(plist_value "$receipt" source_fingerprint)"
  acceptance_root="$(installed_acceptance_root_path "$fingerprint" "$transaction_id")" || {
    echo "Installed acceptance root could not be derived from the transaction." >&2
    return 1
  }
  defaults_suite="$(installed_acceptance_defaults_suite "$fingerprint" "$transaction_id")" || {
    echo "Installed defaults suite could not be derived from the transaction." >&2
    return 1
  }
  validate_installed_acceptance_process "$installed" "$pid" "$acceptance_root" "$defaults_suite" || {
    echo "Installed app is not running with the expected isolated acceptance profile." >&2
    return 1
  }
  process_start_time="$(installed_acceptance_process_start_time \
    "$installed" "$pid" "$acceptance_root" "$defaults_suite")" || {
    echo "Installed acceptance-profile process start identity could not be recorded." >&2
    return 1
  }
  [[ "$process_start_time" =~ ^[1-9][0-9]*$ ]] || {
    echo "Installed acceptance-profile process start identity is malformed." >&2
    return 1
  }
  expected_cdhash="$(plist_value "$receipt" app.cdhash)"
  expected_version="$(plist_value "$receipt" version)"
  expected_build="$(plist_value "$receipt" build)"
  expected_authority="$(plist_value "$receipt" app.authority)"
  expected_executable="$(plist_value "$receipt" app.executable_sha256)"
  expected_certificate="$(plist_value "$receipt" app.certificate_sha256)"
  expected_requirement="$(plist_value "$receipt" app.designated_requirement_sha256)"
  expected_entitlements="$(plist_value "$receipt" app.entitlements_sha256)"
  [[ "$(app_cdhash "$installed")" == "$expected_cdhash" &&
    "$(app_version "$installed")" == "$expected_version" &&
    "$(app_build "$installed")" == "$expected_build" &&
    "$(app_authority "$installed")" == "$expected_authority" &&
    "$(app_executable_sha256 "$installed")" == "$expected_executable" &&
    "$(app_certificate_sha256 "$installed")" == "$expected_certificate" &&
    "$(app_designated_requirement_sha256 "$installed")" == "$expected_requirement" &&
    "$(app_entitlements_sha256 "$installed")" == "$expected_entitlements" ]] || {
    echo "Installed app does not match the accepted candidate." >&2
    return 1
  }
  installed_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  launch_provenance="$(capture_installed_launch \
    "$installed" "$pid" "$process_start_time" "$acceptance_root" "$defaults_suite" \
    "$fingerprint" "$transaction_id" "$installed_at" "$expected_cdhash" \
    "$expected_executable")" || return 1
  update_receipt "$receipt" \
    verification.installed passed \
    verification.installed_path "$installed" \
    verification.installed_cdhash "$expected_cdhash" \
    verification.installed_certificate_sha256 "$expected_certificate" \
    verification.installed_designated_requirement_sha256 "$expected_requirement" \
    verification.installed_entitlements_sha256 "$expected_entitlements" \
    verification.installed_pid "$pid" \
    verification.installed_process_start_time_us "$process_start_time" \
    verification.installed_acceptance_root "$acceptance_root" \
    verification.installed_defaults_suite "$defaults_suite" \
    verification.install_transaction_id "$transaction_id" \
    verification.computer_use pending \
    verification.computer_use_evidence "" \
    verification.computer_use_evidence_sha256 "" \
    verification.computer_use_scenarios "" \
    verification.computer_use_screenshots_manifest "" \
    verification.computer_use_screenshots_sha256 "" \
    verification.computer_use_contact_sheet "" \
    verification.computer_use_contact_sheet_sha256 "" \
    verification.computer_use_scenario_screenshots_sha256 "" \
    verification.computer_use_provenance_manifest "" \
    verification.computer_use_provenance_manifest_sha256 "" \
    verification.computer_use_at "" \
    verification.installed_at "$installed_at"
  printf '%s\n' "$receipt"
}

installed_transaction_valid() {
  [[ $# -eq 2 ]] || usage
  local transaction_id="$1"
  local installed="$2"
  local receipt
  valid_install_transaction_id "$transaction_id" || {
    echo "Install transaction ID must be a lowercase RFC 4122 UUID." >&2
    return 1
  }
  receipt="$(require_candidate 1)"
  [[ "$(plist_value "$receipt" verification.installed)" == passed &&
    "$(plist_value "$receipt" verification.install_transaction_id)" == "$transaction_id" &&
    "$installed" == /Applications/LexiRay.app &&
    "$(plist_value "$receipt" verification.installed_path)" == "$installed" ]] || {
    echo "Installed receipt is not bound to transaction $transaction_id and $installed." >&2
    return 1
  }
  app_matches_receipt "$receipt" "$installed" || {
    echo "Installed app no longer matches transaction $transaction_id." >&2
    return 1
  }
  printf '%s\n' "$receipt"
}

verify_app_match() {
  [[ $# -eq 1 ]] || usage
  local app="$1"
  local receipt installed_path installed_pid installed_root installed_suite evidence_hash
  receipt="$(require_candidate 1)"
  app_matches_receipt "$receipt" "$app" || {
    echo "App does not exactly match the accepted candidate: $app" >&2
    return 1
  }
  printf '%s\n' "$receipt"
}

require_evidence_file() {
  local evidence="$1"
  [[ -n "$evidence" && -f "$evidence" && ! -L "$evidence" && -s "$evidence" ]] || {
    echo "Evidence must be a non-empty file." >&2
    return 1
  }
  case "$evidence" in
    "$ROOT_DIR"/build/ui-artifacts/*|"$ROOT_DIR"/build/acceptance/*) ;;
    *) echo "Evidence must live under the ignored build evidence directories." >&2; return 1 ;;
  esac
}

sha256_joined_values() {
  local value
  for value in "$@"; do
    printf '%s\n' "$value"
  done | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}'
}

valid_utc_timestamp() {
  [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

utc_timestamp_not_after() {
  valid_utc_timestamp "$1" && valid_utc_timestamp "$2" &&
    [[ "$1" == "$2" || "$1" < "$2" ]]
}

utc_timestamp_not_future() {
  utc_timestamp_not_after "$1" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
}

verify_screenshot_manifest() {
  local manifest="$1"
  local expected_count="$2"
  local gui_artifact_dir="${3:-}"
  local line recorded_hash screenshot actual_hash count=0
  local -a screenshots=()
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    recorded_hash="${line%%  *}"
    screenshot="${line#*  }"
    [[ "$recorded_hash" =~ ^[0-9a-f]{64}$ && "$screenshot" != "$line" &&
      "$screenshot" == *.png ]] || return 1
    if [[ -n "$gui_artifact_dir" ]]; then
      require_gui_artifact_directory "$gui_artifact_dir" >/dev/null || return 1
      case "$screenshot" in
        "$gui_artifact_dir"/*) ;;
        *) return 1 ;;
      esac
      require_gui_artifact_file "$screenshot" >/dev/null || return 1
    else
      require_evidence_file "$screenshot" >/dev/null || return 1
    fi
    actual_hash="$(sha256_file "$screenshot")"
    [[ "$actual_hash" == "$recorded_hash" ]] || return 1
    screenshots+=("$screenshot")
    count=$((count + 1))
  done <"$manifest"
  [[ "$count" -eq "$expected_count" && "$count" -gt 0 ]] || return 1
  /usr/bin/swift "$EVIDENCE_HELPER" png "${screenshots[@]}" >/dev/null
}

rebuild_gui_contact_sheet() {
  [[ $# -eq 3 ]] || return 1
  local screenshots_manifest="$1"
  local artifact_dir="$2"
  local output="$3"
  local input_dir line screenshot basename count=0

  require_gui_artifact_directory "$artifact_dir" >/dev/null || return 1
  input_dir="$(mktemp -d "${TMPDIR:-/tmp}/lexiray-gui-contact-verify.XXXXXX")"
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    screenshot="${line#*  }"
    basename="${screenshot##*/}"
    [[ "$screenshot" != "$line" &&
      "$screenshot" == "$artifact_dir/$basename" &&
      "$basename" == *.png &&
      "$basename" != contact-sheet.png &&
      ! -e "$input_dir/$basename" ]] || {
      rm -rf "$input_dir"
      return 1
    }
    cp "$screenshot" "$input_dir/$basename" || {
      rm -rf "$input_dir"
      return 1
    }
    count=$((count + 1))
  done <"$screenshots_manifest"
  [[ "$count" -gt 0 ]] || {
    rm -rf "$input_dir"
    return 1
  }
  "$ROOT_DIR/script/make_contact_sheet.swift" "$input_dir" "$output" >/dev/null || {
    rm -rf "$input_dir"
    return 1
  }
  rm -rf "$input_dir"
}

rebuild_computer_use_contact_sheet() {
  local screenshots_manifest="$1"
  local output="$2"
  local input_dir line screenshot basename scenario index=0
  input_dir="$(mktemp -d "${TMPDIR:-/tmp}/lexiray-cu-contact-verify.XXXXXX")"
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    screenshot="${line#*  }"
    basename="${screenshot##*/}"
    scenario="${basename%%-window-*}"
    [[ "$screenshot" != "$line" && "$basename" == "$scenario-window-"*.png ]] &&
      valid_computer_use_scenario "$scenario" || {
      rm -rf "$input_dir"
      return 1
    }
    index=$((index + 1))
    cp "$screenshot" "$input_dir/$(printf '%02d' "$index")-$scenario-$basename" || {
      rm -rf "$input_dir"
      return 1
    }
  done <"$screenshots_manifest"
  [[ "$index" -gt 0 ]] || {
    rm -rf "$input_dir"
    return 1
  }
  "$ROOT_DIR/script/make_contact_sheet.swift" "$input_dir" "$output" >/dev/null || {
    rm -rf "$input_dir"
    return 1
  }
  rm -rf "$input_dir"
}

computer_use_matrix() {
  printf '%s\n' "${COMPUTER_USE_REQUIRED_SCENARIOS[@]}"
}

computer_use_matrix_csv() {
  computer_use_matrix | paste -sd, -
}

required_computer_use_scenario() {
  local expected
  for expected in "${COMPUTER_USE_REQUIRED_SCENARIOS[@]}"; do
    [[ "$1" == "$expected" ]] && return 0
  done
  return 1
}

computer_use_capture_root() {
  local receipt="$1"
  local transaction_id
  transaction_id="$(plist_value "$receipt" verification.install_transaction_id)"
  valid_install_transaction_id "$transaction_id" || return 1
  printf '%s/computer-use-captures-%s-%s\n' \
    "$ACCEPTANCE_DIR" "$(plist_value "$receipt" source_fingerprint)" "$transaction_id"
}

verify_computer_use_provenance() {
  local receipt="$1"
  local provenance="$2"
  local scenario="$3"
  local require_live="${4:-0}"
  local print_images="${5:-0}"
  local valid_through="${6:-$(date -u '+%Y-%m-%dT%H:%M:%SZ')}"
  local installed_path installed_pid installed_process_start installed_root installed_suite
  local capture_root fingerprint transaction_id installed_at
  local -a expected_arguments
  installed_path="$(plist_value "$receipt" verification.installed_path)"
  installed_pid="$(plist_value "$receipt" verification.installed_pid)"
  installed_process_start="$(plist_value "$receipt" verification.installed_process_start_time_us)"
  installed_root="$(plist_value "$receipt" verification.installed_acceptance_root)"
  installed_suite="$(plist_value "$receipt" verification.installed_defaults_suite)"
  fingerprint="$(plist_value "$receipt" source_fingerprint)"
  transaction_id="$(plist_value "$receipt" verification.install_transaction_id)"
  installed_at="$(plist_value "$receipt" verification.installed_at)"
  capture_root="$(computer_use_capture_root "$receipt")"
  expected_arguments=(
    --lexiray-acceptance-profile
    --lexiray-acceptance-workspace-root "$ROOT_DIR"
    --lexiray-acceptance-root "$installed_root"
    --lexiray-acceptance-defaults-suite "$installed_suite"
    --lexiray-acceptance-login-item-status notFound
  )
  /usr/bin/swift "$EVIDENCE_HELPER" verify \
    "$provenance" "$installed_pid" "$installed_path/Contents/MacOS/LexiRay" \
    "$scenario" "$capture_root" "$fingerprint" \
    "$(plist_value "$receipt" app.cdhash)" \
    "$(plist_value "$receipt" app.executable_sha256)" \
    "$transaction_id" "$installed_at" "$installed_process_start" "$valid_through" \
    "$require_live" "$print_images" -- "${expected_arguments[@]}"
}

capture_computer_use() {
  [[ $# -ge 1 && $# -le 2 ]] || usage
  local scenario="$1"
  local window_id="${2:-}"
  local receipt fingerprint installed_path installed_pid installed_process_start
  local installed_root installed_suite capture_root provenance
  local transaction_id installed_at
  local -a expected_arguments helper_arguments
  valid_computer_use_scenario "$scenario" || {
    echo "Unknown Computer Use scenario: $scenario" >&2
    return 1
  }
  [[ -z "$window_id" || "$window_id" =~ ^[1-9][0-9]*$ ]] || {
    echo "Computer Use window ID must be a positive CGWindow ID." >&2
    return 1
  }
  receipt="$(require_candidate 1)"
  load_computer_use_required_scenarios "$receipt" || return 1
  required_computer_use_scenario "$scenario" || {
    echo "Computer Use scenario is not required by this candidate: $scenario" >&2
    return 1
  }
  [[ "$(plist_value "$receipt" verification.installed)" == passed ]] || {
    echo "Computer Use capture requires an installed candidate." >&2
    return 1
  }
  fingerprint="$(plist_value "$receipt" source_fingerprint)"
  installed_path="$(plist_value "$receipt" verification.installed_path)"
  installed_pid="$(plist_value "$receipt" verification.installed_pid)"
  installed_process_start="$(plist_value "$receipt" verification.installed_process_start_time_us)"
  installed_root="$(plist_value "$receipt" verification.installed_acceptance_root)"
  installed_suite="$(plist_value "$receipt" verification.installed_defaults_suite)"
  transaction_id="$(plist_value "$receipt" verification.install_transaction_id)"
  installed_at="$(plist_value "$receipt" verification.installed_at)"
  capture_root="$(computer_use_capture_root "$receipt")"
  app_matches_receipt "$receipt" "$installed_path" || {
    echo "Installed app became stale before Computer Use capture." >&2
    return 1
  }
  validate_installed_acceptance_process \
    "$installed_path" "$installed_pid" "$installed_root" "$installed_suite" \
    "$installed_process_start" || {
    echo "Installed acceptance-profile process is no longer running or isolated." >&2
    return 1
  }
  if [[ "$scenario" == launch ]]; then
    provenance="$capture_root/launch.json"
    require_evidence_file "$provenance" || {
      echo "Launch evidence must be sealed during canonical installation." >&2
      return 1
    }
    verify_computer_use_provenance "$receipt" "$provenance" "$scenario" 1 0
    printf '%s\n' "$provenance"
    return
  fi
  case "$capture_root" in
    "$ROOT_DIR"/build/acceptance/*) ;;
    *) echo "Computer Use capture root escaped build/acceptance." >&2; return 1 ;;
  esac
  mkdir -p "$capture_root"
  [[ ! -L "$capture_root" ]] || {
    echo "Computer Use capture root must not be a symlink." >&2
    return 1
  }
  expected_arguments=(
    --lexiray-acceptance-profile
    --lexiray-acceptance-workspace-root "$ROOT_DIR"
    --lexiray-acceptance-root "$installed_root"
    --lexiray-acceptance-defaults-suite "$installed_suite"
    --lexiray-acceptance-login-item-status notFound
  )
  helper_arguments=(
    capture "$installed_pid" "$installed_path/Contents/MacOS/LexiRay"
    "$scenario" "$capture_root" "$fingerprint"
    "$(plist_value "$receipt" app.cdhash)"
    "$(plist_value "$receipt" app.executable_sha256)"
    "$transaction_id" "$installed_at" "$installed_process_start"
  )
  [[ -z "$window_id" ]] || helper_arguments+=("$window_id")
  provenance="$(/usr/bin/swift "$EVIDENCE_HELPER" \
    "${helper_arguments[@]}" -- "${expected_arguments[@]}")"
  require_evidence_file "$provenance"
  verify_computer_use_provenance "$receipt" "$provenance" "$scenario" 1 0
  printf '%s\n' "$provenance"
}

validate_computer_use_manifest() {
  local receipt="$1"
  local manifest="$2"
  local require_live="${3:-0}"
  local installed_path installed_pid installed_process_start installed_root installed_suite
  local fingerprint capture_root transaction_id installed_at created_at
  local scenarios expected_scenarios screenshots_manifest screenshots_hash contact_sheet contact_sheet_hash
  local provenance_manifest provenance_manifest_hash combined_hash expected_screenshots expected_scenario
  local recorded_hash scenario provenance extra image image_hash scenario_count=0 screenshot_count
  local rebuilt_contact_sheet

  require_evidence_file "$manifest" || return 1
  load_computer_use_required_scenarios "$receipt" || return 1
  validate_plist "$manifest" || {
    echo "Computer Use manifest is malformed." >&2
    return 1
  }
  installed_path="$(plist_value "$receipt" verification.installed_path)"
  installed_pid="$(plist_value "$receipt" verification.installed_pid)"
  installed_process_start="$(plist_value "$receipt" verification.installed_process_start_time_us)"
  installed_root="$(plist_value "$receipt" verification.installed_acceptance_root)"
  installed_suite="$(plist_value "$receipt" verification.installed_defaults_suite)"
  fingerprint="$(plist_value "$receipt" source_fingerprint)"
  transaction_id="$(plist_value "$receipt" verification.install_transaction_id)"
  installed_at="$(plist_value "$receipt" verification.installed_at)"
  capture_root="$(computer_use_capture_root "$receipt")"
  expected_scenarios="$(computer_use_matrix_csv)"
  scenarios="$(plist_value "$manifest" scenarios)"
  screenshots_manifest="$(plist_value "$manifest" screenshots_manifest)"
  screenshots_hash="$(plist_value "$manifest" screenshots_sha256)"
  contact_sheet="$(plist_value "$manifest" contact_sheet)"
  contact_sheet_hash="$(plist_value "$manifest" contact_sheet_sha256)"
  provenance_manifest="$(plist_value "$manifest" scenario_provenance_manifest)"
  provenance_manifest_hash="$(plist_value "$manifest" scenario_provenance_manifest_sha256)"
  combined_hash="$(plist_value "$manifest" scenario_screenshots_sha256)"
  screenshot_count="$(plist_value "$manifest" screenshot_count)"
  created_at="$(plist_value "$manifest" created_at)"

  [[ "$(plist_value "$manifest" schema_version)" == 4 &&
    "$(plist_value "$manifest" kind)" == computer-use &&
    "$(plist_value "$manifest" status)" == passed &&
    "$(plist_value "$manifest" source_fingerprint)" == "$fingerprint" &&
    "$(plist_value "$manifest" installed_path)" == "$installed_path" &&
    "$(plist_value "$manifest" installed_pid)" == "$installed_pid" &&
    "$(plist_value "$manifest" installed_process_start_time_us)" == "$installed_process_start" &&
    "$(plist_value "$manifest" app_cdhash)" == "$(plist_value "$receipt" app.cdhash)" &&
    "$(plist_value "$manifest" app_executable_sha256)" == "$(plist_value "$receipt" app.executable_sha256)" &&
    "$(plist_value "$manifest" app_certificate_sha256)" == "$(plist_value "$receipt" app.certificate_sha256)" &&
    "$(plist_value "$manifest" app_designated_requirement_sha256)" == "$(plist_value "$receipt" app.designated_requirement_sha256)" &&
    "$(plist_value "$manifest" app_entitlements_sha256)" == "$(plist_value "$receipt" app.entitlements_sha256)" &&
    "$(plist_value "$manifest" acceptance_root)" == "$installed_root" &&
    "$(plist_value "$manifest" defaults_suite)" == "$installed_suite" &&
    "$(plist_value "$manifest" install_transaction_id)" == "$transaction_id" &&
    "$(plist_value "$manifest" installed_at)" == "$installed_at" &&
    "$scenarios" == "$expected_scenarios" &&
    "$(plist_value "$manifest" scenario_count)" == "${#COMPUTER_USE_REQUIRED_SCENARIOS[@]}" ]] || {
    echo "Computer Use manifest is not bound to the canonical matrix, installed process, and app identity." >&2
    return 1
  }
  [[ "$manifest" == "$ACCEPTANCE_DIR/computer-use-$fingerprint-$transaction_id.json" &&
    "$installed_process_start" =~ ^[1-9][0-9]*$ ]] &&
    utc_timestamp_not_after "$installed_at" "$created_at" &&
    utc_timestamp_not_future "$created_at" || {
    echo "Computer Use manifest has a non-canonical path, process start identity, or time interval." >&2
    return 1
  }
  [[ "$provenance_manifest" == "$ACCEPTANCE_DIR/computer-use-provenance-$fingerprint-$transaction_id.sha256" &&
    "$screenshots_manifest" == "$ACCEPTANCE_DIR/computer-use-screenshots-$fingerprint-$transaction_id.sha256" &&
    "$contact_sheet" == "$ACCEPTANCE_DIR/computer-use-contact-sheet-$fingerprint-$transaction_id.png" ]] || {
    echo "Computer Use evidence paths are not canonical." >&2
    return 1
  }
  require_evidence_file "$provenance_manifest" || return 1
  require_evidence_file "$screenshots_manifest" || return 1
  require_evidence_file "$contact_sheet" || return 1
  [[ "$provenance_manifest_hash" =~ ^[0-9a-f]{64}$ &&
    "$(sha256_file "$provenance_manifest")" == "$provenance_manifest_hash" &&
    "$screenshots_hash" =~ ^[0-9a-f]{64}$ &&
    "$(sha256_file "$screenshots_manifest")" == "$screenshots_hash" &&
    "$contact_sheet_hash" =~ ^[0-9a-f]{64}$ &&
    "$(sha256_file "$contact_sheet")" == "$contact_sheet_hash" &&
    "$screenshot_count" =~ ^[1-9][0-9]*$ &&
    "$combined_hash" == "$(sha256_joined_values \
      "$scenarios" "$provenance_manifest_hash" "$screenshots_hash" "$contact_sheet_hash")" ]] || {
    echo "Computer Use provenance/screenshot/contact-sheet hashes do not match." >&2
    return 1
  }
  /usr/bin/swift "$EVIDENCE_HELPER" png "$contact_sheet" >/dev/null || {
    echo "Computer Use contact sheet is not a real PNG." >&2
    return 1
  }

  expected_screenshots="$(mktemp "${TMPDIR:-/tmp}/lexiray-cu-screenshots.XXXXXX")"
  : >"$expected_screenshots"
  while IFS=$'\t' read -r recorded_hash scenario provenance extra; do
    [[ -n "$recorded_hash" || -n "$scenario" || -n "$provenance" ]] || continue
    [[ -z "$extra" && "$recorded_hash" =~ ^[0-9a-f]{64}$ &&
      "$scenario_count" -lt "${#COMPUTER_USE_REQUIRED_SCENARIOS[@]}" ]] || {
      rm -f "$expected_screenshots"
      echo "Computer Use provenance manifest is malformed." >&2
      return 1
    }
    expected_scenario="${COMPUTER_USE_REQUIRED_SCENARIOS[$scenario_count]}"
    [[ "$scenario" == "$expected_scenario" &&
      "$provenance" == "$capture_root/$scenario.json" ]] || {
      rm -f "$expected_screenshots"
      echo "Computer Use provenance does not cover the canonical matrix in order." >&2
      return 1
    }
    require_evidence_file "$provenance" >/dev/null || {
      rm -f "$expected_screenshots"
      return 1
    }
    [[ "$(sha256_file "$provenance")" == "$recorded_hash" ]] || {
      rm -f "$expected_screenshots"
      echo "Computer Use provenance hash is stale for $scenario." >&2
      return 1
    }
    # Scenario states are sequential: no installed app can remain in the
    # source-editor, speech, non-key-panel, and OCR-overlay states at once.
    # Capture already performed the live AX/window assertions. Manifest
    # validation replays the sealed provenance, then checks the exact process
    # once below when the caller requires a live handoff.
    if ! images="$(verify_computer_use_provenance \
      "$receipt" "$provenance" "$scenario" 0 1 "$created_at")"; then
      rm -f "$expected_screenshots"
      echo "Computer Use provenance is invalid for $scenario." >&2
      return 1
    fi
    [[ -n "$images" ]] || {
      rm -f "$expected_screenshots"
      echo "Computer Use provenance has no PNG for $scenario." >&2
      return 1
    }
    while IFS= read -r image; do
      [[ -n "$image" ]] || continue
      image_hash="$(sha256_file "$image")"
      printf '%s  %s\n' "$image_hash" "$image" >>"$expected_screenshots"
    done <<<"$images"
    scenario_count=$((scenario_count + 1))
  done <"$provenance_manifest"
  [[ "$scenario_count" -eq "${#COMPUTER_USE_REQUIRED_SCENARIOS[@]}" &&
    -s "$expected_screenshots" ]] &&
    cmp -s "$expected_screenshots" "$screenshots_manifest" || {
    rm -f "$expected_screenshots"
    echo "Computer Use screenshots are not the exact images sealed by per-scenario provenance." >&2
    return 1
  }
  rm -f "$expected_screenshots"
  verify_screenshot_manifest "$screenshots_manifest" "$screenshot_count" || {
    echo "Computer Use screenshot files no longer match their screenshot manifest." >&2
    return 1
  }
  rebuilt_contact_sheet="$(mktemp "${TMPDIR:-/tmp}/lexiray-cu-contact-sheet.XXXXXX")"
  if ! rebuild_computer_use_contact_sheet "$screenshots_manifest" "$rebuilt_contact_sheet" ||
     [[ "$(sha256_file "$rebuilt_contact_sheet")" != "$contact_sheet_hash" ]] ||
     ! cmp -s "$rebuilt_contact_sheet" "$contact_sheet"; then
    rm -f "$rebuilt_contact_sheet"
    echo "Computer Use contact sheet is not derived from the sealed scenario screenshots." >&2
    return 1
  fi
  rm -f "$rebuilt_contact_sheet"
  if [[ "$require_live" == 1 ]]; then
    validate_installed_acceptance_process \
      "$installed_path" "$installed_pid" "$installed_root" "$installed_suite" \
      "$installed_process_start" || {
      echo "Installed acceptance-profile process is no longer running or isolated." >&2
      return 1
    }
  fi
}

write_computer_use_manifest() {
  [[ $# -eq 0 ]] || usage
  local receipt fingerprint installed_path installed_pid installed_process_start
  local installed_root installed_suite capture_root scenarios transaction_id installed_at created_at
  local provenance_manifest provenance_hash screenshot_manifest screenshot_count screenshot_hash
  local contact_sheet contact_hash combined_hash manifest plist input_dir scenario provenance images image index=0

  receipt="$(require_candidate 1)"
  load_computer_use_required_scenarios "$receipt" || return 1
  [[ "$(plist_value "$receipt" verification.installed)" == passed ]] || {
    echo "Computer Use evidence requires an installed candidate." >&2
    return 1
  }
  fingerprint="$(plist_value "$receipt" source_fingerprint)"
  installed_path="$(plist_value "$receipt" verification.installed_path)"
  installed_pid="$(plist_value "$receipt" verification.installed_pid)"
  installed_process_start="$(plist_value "$receipt" verification.installed_process_start_time_us)"
  installed_root="$(plist_value "$receipt" verification.installed_acceptance_root)"
  installed_suite="$(plist_value "$receipt" verification.installed_defaults_suite)"
  transaction_id="$(plist_value "$receipt" verification.install_transaction_id)"
  installed_at="$(plist_value "$receipt" verification.installed_at)"
  capture_root="$(computer_use_capture_root "$receipt")"
  scenarios="$(computer_use_matrix_csv)"
  app_matches_receipt "$receipt" "$installed_path" || {
    echo "Installed app became stale before Computer Use evidence was recorded." >&2
    return 1
  }
  validate_installed_acceptance_process \
    "$installed_path" "$installed_pid" "$installed_root" "$installed_suite" \
    "$installed_process_start" || {
    echo "Installed acceptance-profile process is no longer running or isolated." >&2
    return 1
  }

  mkdir -p "$ACCEPTANCE_DIR"
  provenance_manifest="$ACCEPTANCE_DIR/computer-use-provenance-$fingerprint-$transaction_id.sha256"
  screenshot_manifest="$ACCEPTANCE_DIR/computer-use-screenshots-$fingerprint-$transaction_id.sha256"
  contact_sheet="$ACCEPTANCE_DIR/computer-use-contact-sheet-$fingerprint-$transaction_id.png"
  : >"$provenance_manifest"
  : >"$screenshot_manifest"
  input_dir="$(mktemp -d "${TMPDIR:-/tmp}/lexiray-cu-contact.XXXXXX")"
  for scenario in "${COMPUTER_USE_REQUIRED_SCENARIOS[@]}"; do
    provenance="$capture_root/$scenario.json"
    require_evidence_file "$provenance" || {
      rm -rf "$input_dir"
      echo "Missing Computer Use capture for canonical scenario: $scenario" >&2
      return 1
    }
    if ! images="$(verify_computer_use_provenance "$receipt" "$provenance" "$scenario" 0 1)"; then
      rm -rf "$input_dir"
      echo "Invalid Computer Use capture for canonical scenario: $scenario" >&2
      return 1
    fi
    [[ -n "$images" ]] || {
      rm -rf "$input_dir"
      echo "Computer Use capture has no PNG for canonical scenario: $scenario" >&2
      return 1
    }
    printf '%s\t%s\t%s\n' "$(sha256_file "$provenance")" "$scenario" "$provenance" >>"$provenance_manifest"
    while IFS= read -r image; do
      [[ -n "$image" ]] || continue
      printf '%s  %s\n' "$(sha256_file "$image")" "$image" >>"$screenshot_manifest"
      index=$((index + 1))
      cp "$image" "$input_dir/$(printf '%02d' "$index")-$scenario-${image##*/}"
    done <<<"$images"
  done
  screenshot_count="$(/usr/bin/awk 'NF { count++ } END { print count + 0 }' "$screenshot_manifest")"
  [[ "$screenshot_count" -ge "${#COMPUTER_USE_REQUIRED_SCENARIOS[@]}" ]] || {
    rm -rf "$input_dir"
    echo "Computer Use canonical matrix does not have at least one PNG per scenario." >&2
    return 1
  }
  "$ROOT_DIR/script/make_contact_sheet.swift" "$input_dir" "$contact_sheet" >/dev/null
  rm -rf "$input_dir"
  /usr/bin/swift "$EVIDENCE_HELPER" png "$contact_sheet" >/dev/null
  provenance_hash="$(sha256_file "$provenance_manifest")"
  screenshot_hash="$(sha256_file "$screenshot_manifest")"
  contact_hash="$(sha256_file "$contact_sheet")"
  combined_hash="$(sha256_joined_values \
    "$scenarios" "$provenance_hash" "$screenshot_hash" "$contact_hash")"
  created_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  manifest="$ACCEPTANCE_DIR/computer-use-$fingerprint-$transaction_id.json"
  plist="$(mktemp "$ACCEPTANCE_DIR/.computer-use-plist.XXXXXX")"
  /usr/bin/plutil -create xml1 "$plist"
  /usr/bin/plutil -insert schema_version -integer 4 -- "$plist"
  plist_insert_string "$plist" kind computer-use
  plist_insert_string "$plist" status passed
  plist_insert_string "$plist" source_fingerprint "$fingerprint"
  plist_insert_string "$plist" installed_path "$installed_path"
  plist_insert_string "$plist" installed_pid "$installed_pid"
  plist_insert_string "$plist" installed_process_start_time_us "$installed_process_start"
  plist_insert_string "$plist" app_cdhash "$(plist_value "$receipt" app.cdhash)"
  plist_insert_string "$plist" app_executable_sha256 "$(plist_value "$receipt" app.executable_sha256)"
  plist_insert_string "$plist" app_certificate_sha256 "$(plist_value "$receipt" app.certificate_sha256)"
  plist_insert_string "$plist" app_designated_requirement_sha256 "$(plist_value "$receipt" app.designated_requirement_sha256)"
  plist_insert_string "$plist" app_entitlements_sha256 "$(plist_value "$receipt" app.entitlements_sha256)"
  plist_insert_string "$plist" acceptance_root "$installed_root"
  plist_insert_string "$plist" defaults_suite "$installed_suite"
  plist_insert_string "$plist" install_transaction_id "$transaction_id"
  plist_insert_string "$plist" installed_at "$installed_at"
  plist_insert_string "$plist" scenarios "$scenarios"
  /usr/bin/plutil -insert scenario_count -integer "${#COMPUTER_USE_REQUIRED_SCENARIOS[@]}" -- "$plist"
  plist_insert_string "$plist" scenario_provenance_manifest "$provenance_manifest"
  plist_insert_string "$plist" scenario_provenance_manifest_sha256 "$provenance_hash"
  plist_insert_string "$plist" screenshots_manifest "$screenshot_manifest"
  plist_insert_string "$plist" screenshots_sha256 "$screenshot_hash"
  /usr/bin/plutil -insert screenshot_count -integer "$screenshot_count" -- "$plist"
  plist_insert_string "$plist" contact_sheet "$contact_sheet"
  plist_insert_string "$plist" contact_sheet_sha256 "$contact_hash"
  plist_insert_string "$plist" scenario_screenshots_sha256 "$combined_hash"
  plist_insert_string "$plist" created_at "$created_at"
  /usr/bin/plutil -convert json -r -o "$manifest" -- "$plist"
  rm -f "$plist"
  chmod 600 "$manifest" "$provenance_manifest" "$screenshot_manifest" "$contact_sheet"
  validate_computer_use_manifest "$receipt" "$manifest" 1
  printf '%s\n' "$manifest"
}

computer_use_receipt_matches_manifest() {
  local receipt="$1"
  local manifest="$2"
  local completed_at created_at
  completed_at="$(plist_value "$receipt" verification.computer_use_at)"
  created_at="$(plist_value "$manifest" created_at)"
  [[ "$(plist_value "$receipt" verification.computer_use)" == passed &&
    "$(plist_value "$receipt" verification.computer_use_evidence)" == "$manifest" &&
    "$(plist_value "$receipt" verification.computer_use_evidence_sha256)" == "$(sha256_file "$manifest")" &&
    "$(plist_value "$receipt" verification.computer_use_scenarios)" == "$(plist_value "$manifest" scenarios)" &&
    "$(plist_value "$receipt" verification.computer_use_screenshots_manifest)" == "$(plist_value "$manifest" screenshots_manifest)" &&
    "$(plist_value "$receipt" verification.computer_use_screenshots_sha256)" == "$(plist_value "$manifest" screenshots_sha256)" &&
    "$(plist_value "$receipt" verification.computer_use_contact_sheet)" == "$(plist_value "$manifest" contact_sheet)" &&
    "$(plist_value "$receipt" verification.computer_use_contact_sheet_sha256)" == "$(plist_value "$manifest" contact_sheet_sha256)" &&
    "$(plist_value "$receipt" verification.computer_use_scenario_screenshots_sha256)" == "$(plist_value "$manifest" scenario_screenshots_sha256)" &&
    "$(plist_value "$receipt" verification.computer_use_provenance_manifest)" == "$(plist_value "$manifest" scenario_provenance_manifest)" &&
    "$(plist_value "$receipt" verification.computer_use_provenance_manifest_sha256)" == "$(plist_value "$manifest" scenario_provenance_manifest_sha256)" ]] &&
    utc_timestamp_not_after "$created_at" "$completed_at" &&
    utc_timestamp_not_future "$completed_at" || {
    echo "Computer Use receipt fields do not exactly mirror the sealed manifest." >&2
    return 1
  }
}

mark_computer_use() {
  [[ $# -eq 2 ]] || usage
  local status="$1"
  local evidence="${2:-}"
  local receipt installed_path installed_pid installed_root installed_suite evidence_hash
  local contact_sheet contact_sheet_hash scenarios screenshots_manifest screenshots_hash combined_hash
  local provenance_manifest provenance_manifest_hash completed_at
  case "$status" in
    passed|failed|blocked) ;;
    *) echo "Computer Use status must be passed, failed, or blocked." >&2; exit 2 ;;
  esac
  receipt="$(require_candidate 1)"
  if [[ "$status" == passed && "$(plist_value "$receipt" verification.installed)" != passed ]]; then
    echo "Computer Use cannot pass before the installed app is verified." >&2
    return 1
  fi
  if [[ "$status" == passed ]]; then
    require_evidence_file "$evidence"
    installed_path="$(plist_value "$receipt" verification.installed_path)"
    installed_pid="$(plist_value "$receipt" verification.installed_pid)"
    installed_root="$(plist_value "$receipt" verification.installed_acceptance_root)"
    installed_suite="$(plist_value "$receipt" verification.installed_defaults_suite)"
    [[ "$installed_path" == /Applications/LexiRay.app ]] || {
      echo "Computer Use must target /Applications/LexiRay.app." >&2
      return 1
    }
    app_matches_receipt "$receipt" "$installed_path" || {
      echo "Installed app became stale before Computer Use acceptance." >&2
      return 1
    }
    validate_computer_use_manifest "$receipt" "$evidence" 1
    contact_sheet="$(plist_value "$evidence" contact_sheet)"
    contact_sheet_hash="$(plist_value "$evidence" contact_sheet_sha256)"
    scenarios="$(plist_value "$evidence" scenarios)"
    screenshots_manifest="$(plist_value "$evidence" screenshots_manifest)"
    screenshots_hash="$(plist_value "$evidence" screenshots_sha256)"
    provenance_manifest="$(plist_value "$evidence" scenario_provenance_manifest)"
    provenance_manifest_hash="$(plist_value "$evidence" scenario_provenance_manifest_sha256)"
    combined_hash="$(plist_value "$evidence" scenario_screenshots_sha256)"
    evidence_hash="$(sha256_file "$evidence")"
    completed_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    utc_timestamp_not_after "$(plist_value "$evidence" created_at)" "$completed_at" || {
      echo "Computer Use manifest creation time is after the acceptance mark." >&2
      return 1
    }
  else
    require_evidence_file "$evidence"
    evidence_hash="$(sha256_file "$evidence")"
    contact_sheet=""
    contact_sheet_hash=""
    scenarios=""
    screenshots_manifest=""
    screenshots_hash=""
    provenance_manifest=""
    provenance_manifest_hash=""
    combined_hash=""
    completed_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  fi
  update_receipt "$receipt" \
    verification.computer_use "$status" \
    verification.computer_use_evidence "$evidence" \
    verification.computer_use_evidence_sha256 "$evidence_hash" \
    verification.computer_use_scenarios "$scenarios" \
    verification.computer_use_screenshots_manifest "$screenshots_manifest" \
    verification.computer_use_screenshots_sha256 "$screenshots_hash" \
    verification.computer_use_contact_sheet "$contact_sheet" \
    verification.computer_use_contact_sheet_sha256 "$contact_sheet_hash" \
    verification.computer_use_scenario_screenshots_sha256 "$combined_hash" \
    verification.computer_use_provenance_manifest "$provenance_manifest" \
    verification.computer_use_provenance_manifest_sha256 "$provenance_manifest_hash" \
    verification.computer_use_at "$completed_at"
  if [[ "$status" == passed ]]; then
    computer_use_receipt_matches_manifest "$receipt" "$evidence"
  fi
  printf '%s\n' "$receipt"
}

require_handoff() {
  [[ $# -eq 0 ]] || usage
  local receipt installed
  receipt="$(require_candidate 1)"
  [[ "$(plist_value "$receipt" verification.installed)" == passed ]] || {
    echo "Handoff requires installed verification." >&2
    return 1
  }
  installed="$(plist_value "$receipt" verification.installed_path)"
  [[ "$installed" == /Applications/LexiRay.app ]] && app_matches_receipt "$receipt" "$installed" || {
    echo "Handoff requires the canonical installed app to match the candidate." >&2
    return 1
  }
  [[ "$(plist_value "$receipt" verification.computer_use)" == passed ]] || {
    echo "Handoff requires installed-app Computer Use verification." >&2
    return 1
  }
  validate_computer_use_manifest \
    "$receipt" "$(plist_value "$receipt" verification.computer_use_evidence)" 0
  if [[ "$(plist_value "$receipt" verification.login_item_system_probe)" != not-required ]]; then
    require_login_item_probe >/dev/null
  fi
  printf '%s\n' "$receipt"
}

if [[ "${LEXIRAY_ACCEPTANCE_LIBRARY_ONLY:-0}" == 1 ]]; then
  return 0 2>/dev/null || exit 0
fi

command="${1:-}"
[[ $# -gt 0 ]] && shift || true
case "$command" in
  fingerprint) [[ $# -eq 0 ]] || usage; source_fingerprint ;;
  path) [[ $# -eq 0 ]] || usage; receipt_path ;;
  l3-path) [[ $# -eq 0 ]] || usage; l3_path ;;
  l3-valid) [[ $# -eq 0 ]] || usage; l3_valid ;;
  record-l3) record_l3 "$@" ;;
  validate-gui-artifact) validate_gui_artifact "$@" ;;
  write-candidate) write_candidate "$@" ;;
  require-automated-candidate) [[ $# -eq 0 ]] || usage; require_candidate 0 ;;
  require-candidate) [[ $# -eq 0 ]] || usage; require_candidate 1 ;;
  field)
    [[ $# -eq 1 ]] || usage
    receipt="$(require_candidate 0)"
    plist_value "$receipt" "$1"
    printf '\n'
    ;;
  mark-gui-inspected) mark_gui_inspected "$@" ;;
  app-identity) write_app_identity "$@" ;;
  computer-use-matrix)
    [[ $# -eq 0 ]] || usage
    receipt="$(require_candidate 0)"
    load_computer_use_required_scenarios "$receipt"
    computer_use_matrix
    ;;
  capture-computer-use) capture_computer_use "$@" ;;
  write-computer-use-manifest) write_computer_use_manifest "$@" ;;
  verify-app-match) verify_app_match "$@" ;;
  mark-installed) mark_installed "$@" ;;
  mark-login-item-probe) mark_login_item_probe "$@" ;;
  require-login-item-probe) require_login_item_probe "$@" ;;
  installed-transaction-valid) installed_transaction_valid "$@" ;;
  mark-computer-use) mark_computer_use "$@" ;;
  require-handoff) require_handoff "$@" ;;
  *) usage ;;
esac

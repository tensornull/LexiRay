#!/usr/bin/env bash
# GUI scenario runner. Builds the workspace app, seeds deterministic fixtures,
# runs each scenario as lib.swift + scenarios/<name>.swift, and stores
# screenshot evidence per run.
#
# Usage:
#   script/ui/run.sh                          # all scenarios
#   script/ui/run.sh panel_blank history_nav  # selected scenarios
#   script/ui/run.sh --skip-build ...         # reuse the existing workspace app
#   script/ui/run.sh --list
#
# Exit codes: 0 all passed, 1 at least one scenario failed, 2 blocked
# (missing permission, unavailable display coverage, or shielded GUI session).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
UI_DIR="$ROOT_DIR/script/ui"
SCENARIO_DIR="$UI_DIR/scenarios"
APP_BUNDLE="$ROOT_DIR/build/DerivedData/Build/Products/Debug/LexiRay.app"
RECEIPT_TOOL="$ROOT_DIR/script/acceptance_receipt.sh"

SCENARIO_ORDER=(launch providers settings_identity panel_blank source_editor language_direction_input speech_controls history_nav rich_result_wrap pin panel_visual_states selection_translate ocr_permission_gate ocr_multi_display manual_resize_preserved streaming_growth)

cd "$ROOT_DIR"

usage() {
  sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

SKIP_BUILD=0
REQUESTED=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-build) SKIP_BUILD=1 ;;
    --list)
      printf '%s\n' "${SCENARIO_ORDER[@]}"
      exit 0
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    -*)
      echo "unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *) REQUESTED+=("$1") ;;
  esac
  shift
done

if [[ ${#REQUESTED[@]} -eq 0 ]]; then
  REQUESTED=("${SCENARIO_ORDER[@]}")
fi

for name in "${REQUESTED[@]}"; do
  if [[ ! -f "$SCENARIO_DIR/$name.swift" ]]; then
    echo "unknown scenario: $name (use --list)" >&2
    exit 2
  fi
done

existing_workspace_pids() {
  local pid command
  (pgrep -x LexiRay || true) | while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    command="$(ps -ww -p "$pid" -o command= 2>/dev/null || true)"
    case "$command" in
      "$ROOT_DIR"/*/LexiRay.app/Contents/MacOS/LexiRay*)
        printf '%s\t%s\n' "$pid" "$command"
        ;;
    esac
  done
}

require_no_existing_workspace_app() {
  local existing
  existing="$(existing_workspace_pids)"
  [[ -z "$existing" ]] || {
    echo "UI_BLOCKED[process]: an existing workspace LexiRay process is running;" \
      "the runner will not terminate it:" >&2
    printf '%s\n' "$existing" | sed 's/^/  /' >&2
    return 1
  }
}

# Never adopt or terminate an app left by a user or an interrupted earlier run.
# Each Swift scenario records and cleans up only the exact PID it launches.
require_no_existing_workspace_app || exit 2

# --- Precheck: the runner process itself needs Accessibility to post events.
if ! swift - <<'SWIFT'
import ApplicationServices
exit(AXIsProcessTrusted() ? 0 : 1)
SWIFT
then
  echo "UI_BLOCKED[precheck]: this terminal/agent process lacks Accessibility permission;" \
    "grant it once in System Settings > Privacy & Security > Accessibility, then rerun" >&2
  exit 2
fi

# Window names and pixels are privacy-redacted without Screen Recording. Block
# before build/scenario work instead of turning missing permission into UI
# failures or incomplete evidence. Never call CGRequestScreenCaptureAccess here;
# verification must not trigger a system authorization prompt.
if ! swift - <<'SWIFT'
import CoreGraphics
exit(CGPreflightScreenCaptureAccess() ? 0 : 1)
SWIFT
then
  echo "UI_BLOCKED[precheck]: this terminal/agent process lacks Screen Recording permission;" \
    "grant it once in System Settings > Privacy & Security > Screen & System Audio Recording, then rerun" >&2
  exit 2
fi

# --- Build (or verify) the canonical workspace app.
if [[ "$SKIP_BUILD" == 1 ]]; then
  if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "UI_BLOCKED[build]: --skip-build was passed but $APP_BUNDLE does not exist" >&2
    exit 2
  fi
else
  ./script/build_and_run.sh --verify >/dev/null
fi

SOURCE_FINGERPRINT="$($RECEIPT_TOOL fingerprint)"
[[ -f "$APP_BUNDLE.source-fingerprint" && "$(<"$APP_BUNDLE.source-fingerprint")" == "$SOURCE_FINGERPRINT" ]] || {
  echo "UI_BLOCKED[build]: workspace app is not attested for source $SOURCE_FINGERPRINT" >&2
  exit 2
}
APP_IDENTITY="$(mktemp "${TMPDIR:-/tmp}/lexiray-ui-identity.XXXXXX")"
if ! "$RECEIPT_TOOL" app-identity "$APP_BUNDLE" >"$APP_IDENTITY"; then
  rm -f "$APP_IDENTITY"
  echo "UI_BLOCKED[build]: workspace app identity could not be recorded" >&2
  exit 2
fi
APP_CDHASH="$(/usr/bin/plutil -extract cdhash raw -n -- "$APP_IDENTITY")"
APP_EXECUTABLE_SHA256="$(/usr/bin/plutil -extract executable_sha256 raw -n -- "$APP_IDENTITY")"
APP_CERTIFICATE_SHA256="$(/usr/bin/plutil -extract certificate_sha256 raw -n -- "$APP_IDENTITY")"
APP_DESIGNATED_REQUIREMENT_SHA256="$(/usr/bin/plutil -extract designated_requirement_sha256 raw -n -- "$APP_IDENTITY")"
APP_ENTITLEMENTS_SHA256="$(/usr/bin/plutil -extract entitlements_sha256 raw -n -- "$APP_IDENTITY")"
rm -f "$APP_IDENTITY"
[[ -n "$APP_CDHASH" && -n "$APP_EXECUTABLE_SHA256" && \
  -n "$APP_CERTIFICATE_SHA256" && -n "$APP_DESIGNATED_REQUIREMENT_SHA256" && \
  -n "$APP_ENTITLEMENTS_SHA256" ]] || {
  echo "UI_BLOCKED[build]: workspace app identity could not be recorded" >&2
  exit 2
}

# --- Evidence and isolated acceptance profile.
RUN_STAMP="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_DIR="${LEXIRAY_UI_ARTIFACT_DIR:-$ROOT_DIR/build/ui-artifacts/$RUN_STAMP}"
ARTIFACT_BASE="$ROOT_DIR/build/ui-artifacts"
ACCEPTANCE_ROOT="$ROOT_DIR/build/acceptance-data/$RUN_STAMP-$$"
ACCEPTANCE_DEFAULTS_SUITE="io.github.tensornull.lexiray.acceptance.$RUN_STAMP.$$"
ACCEPTANCE_PREFERENCES_HOME="$ACCEPTANCE_ROOT/preferences-home"
PROVIDERS_FILE="$ACCEPTANCE_ROOT/providers.json"
HISTORY_FILE="$ACCEPTANCE_ROOT/history.json"

prepare_artifact_dir() {
  local relative component current
  local -a components=()
  case "$ARTIFACT_DIR" in
    "$ARTIFACT_BASE"/*) ;;
    *)
      echo "UI_BLOCKED[evidence]: artifact directory must be below $ARTIFACT_BASE" >&2
      exit 2
      ;;
  esac
  relative="${ARTIFACT_DIR#"$ARTIFACT_BASE"/}"
  [[ -n "$relative" ]] || {
    echo "UI_BLOCKED[evidence]: artifact directory must be a run-specific child" >&2
    exit 2
  }

  for current in "$ROOT_DIR/build" "$ARTIFACT_BASE"; do
    [[ ! -L "$current" ]] || {
      echo "UI_BLOCKED[evidence]: artifact parent must not be a symlink: $current" >&2
      exit 2
    }
    if [[ -e "$current" ]]; then
      [[ -d "$current" ]] || {
        echo "UI_BLOCKED[evidence]: artifact parent is not a directory: $current" >&2
        exit 2
      }
    else
      mkdir "$current"
    fi
    [[ "$(cd "$current" && pwd -P)" == "$current" ]] || {
      echo "UI_BLOCKED[evidence]: artifact parent is not canonical: $current" >&2
      exit 2
    }
  done

  current="$ARTIFACT_BASE"
  IFS='/' read -r -a components <<<"$relative"
  for component in "${components[@]}"; do
    [[ -n "$component" && "$component" != . && "$component" != .. ]] || {
      echo "UI_BLOCKED[evidence]: artifact directory contains an unsafe path component" >&2
      exit 2
    }
    current="$current/$component"
    [[ ! -L "$current" ]] || {
      echo "UI_BLOCKED[evidence]: artifact directory must not contain symlinks: $current" >&2
      exit 2
    }
    if [[ -e "$current" ]]; then
      [[ -d "$current" ]] || {
        echo "UI_BLOCKED[evidence]: artifact path component is not a directory: $current" >&2
        exit 2
      }
    else
      mkdir "$current"
    fi
  done
  [[ "$(cd "$ARTIFACT_DIR" && pwd -P)" == "$ARTIFACT_DIR" ]] || {
    echo "UI_BLOCKED[evidence]: artifact directory escaped its canonical root" >&2
    exit 2
  }
  if find "$ARTIFACT_DIR" -mindepth 1 -print -quit | grep -q .; then
    echo "UI_BLOCKED[evidence]: artifact directory must be empty for a new run" >&2
    exit 2
  fi
}

validate_acceptance_paths() {
  [[ "$ACCEPTANCE_ROOT" == "$ROOT_DIR/build/acceptance-data/"* ]] || {
    echo "UI_BLOCKED[data]: acceptance root escaped the repository build directory" >&2
    exit 2
  }
  [[ "$ACCEPTANCE_DEFAULTS_SUITE" == io.github.tensornull.lexiray.acceptance.* ]] || {
    echo "UI_BLOCKED[data]: invalid acceptance defaults suite" >&2
    exit 2
  }
  for path in \
    "$ROOT_DIR/build" \
    "$ROOT_DIR/build/acceptance-data" \
    "$ACCEPTANCE_ROOT" \
    "$ACCEPTANCE_PREFERENCES_HOME"; do
    [[ ! -L "$path" ]] || {
      echo "UI_BLOCKED[data]: acceptance path must not be a symlink: $path" >&2
      exit 2
    }
  done
  mkdir -p "$ROOT_DIR/build/acceptance-data"
  [[ "$(cd "$ROOT_DIR/build/acceptance-data" && pwd -P)" == "$ROOT_DIR/build/acceptance-data" ]] || {
    echo "UI_BLOCKED[data]: acceptance base did not resolve inside the repository" >&2
    exit 2
  }
}

validate_acceptance_paths
prepare_artifact_dir
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lexiray-ui.XXXXXX")"

# The runner never reads, backs up, replaces, or restores ~/.lexiray or the
# production defaults domain. A killed run can leave only ignored acceptance
# data behind; the real user's providers, keys, history, and defaults remain
# outside the process configuration entirely.

seed_fixture_state() {
  validate_acceptance_paths
  rm -rf "$ACCEPTANCE_ROOT"
  mkdir -p "$ACCEPTANCE_PREFERENCES_HOME"
  printf '%s\n' 'LexiRay acceptance root v1' >"$ACCEPTANCE_ROOT/.lexiray-acceptance-root"
  cp "$UI_DIR/fixtures/providers.json" "$PROVIDERS_FILE"
  cp "$UI_DIR/fixtures/history.json" "$HISTORY_FILE"
  chmod 600 "$ACCEPTANCE_ROOT/.lexiray-acceptance-root" "$PROVIDERS_FILE" "$HISTORY_FILE"
}

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# --- Run scenarios.
declare -a RESULTS=()
FAILED=0
BLOCKED=0

for name in "${REQUESTED[@]}"; do
  if ! require_no_existing_workspace_app; then
    RESULTS+=("BLOCK $name")
    BLOCKED=1
    break
  fi
  seed_fixture_state
  echo "--- scenario: $name"
  set +e
  cat "$UI_DIR/panel_border_evidence.swift" "$UI_DIR/lib.swift" "$SCENARIO_DIR/$name.swift" |
    swift - "$APP_BUNDLE" "$WORK_DIR" "$ARTIFACT_DIR" "$name" "$ROOT_DIR" \
      "$ACCEPTANCE_ROOT" "$ACCEPTANCE_DEFAULTS_SUITE"
  status=$?
  set -e

  case "$status" in
    0) RESULTS+=("PASS  $name") ;;
    2)
      RESULTS+=("BLOCK $name")
      BLOCKED=1
      break
      ;;
    *)
      RESULTS+=("FAIL  $name")
      FAILED=1
      ;;
  esac
done

echo
echo "=== UI scenario results ==="
printf '%s\n' "${RESULTS[@]}"
printf '%s\n' "${RESULTS[@]}" >"$ARTIFACT_DIR/results.txt"
SOURCE_FINGERPRINT_AFTER="$($RECEIPT_TOOL fingerprint)"
if [[ "$SOURCE_FINGERPRINT_AFTER" != "$SOURCE_FINGERPRINT" ]]; then
  echo "UI_FAIL[runner]: source changed during GUI acceptance" >&2
  FAILED=1
fi

manifest_plist="$(mktemp "$ARTIFACT_DIR/.gui-run-plist.XXXXXX")"
manifest_json="$(mktemp "$ARTIFACT_DIR/.gui-run-json.XXXXXX")"
results_sha256="$(/usr/bin/shasum -a 256 "$ARTIFACT_DIR/results.txt" | awk '{print $1}')"
scenario_list="$(printf '%s\n' "${REQUESTED[@]}" | paste -sd, -)"
screenshot_manifest="$ARTIFACT_DIR/gui-screenshots.sha256"
: >"$screenshot_manifest"
while IFS= read -r -d '' screenshot; do
  printf '%s  %s\n' \
    "$(/usr/bin/shasum -a 256 "$screenshot" | /usr/bin/awk '{print $1}')" \
    "$screenshot" >>"$screenshot_manifest"
done < <(find "$ARTIFACT_DIR" -type f -name '*.png' -print0 | LC_ALL=C sort -z)
screenshot_count="$(/usr/bin/awk 'NF { count++ } END { print count + 0 }' "$screenshot_manifest")"
screenshot_manifest_sha256="$(/usr/bin/shasum -a 256 "$screenshot_manifest" | /usr/bin/awk '{print $1}')"
/usr/bin/plutil -create xml1 "$manifest_plist"
/usr/bin/plutil -insert schema_version -integer 1 -- "$manifest_plist"
/usr/bin/plutil -insert kind -string gui-run -- "$manifest_plist"
/usr/bin/plutil -insert source_fingerprint -string "$SOURCE_FINGERPRINT" -- "$manifest_plist"
/usr/bin/plutil -insert app_path -string "$APP_BUNDLE" -- "$manifest_plist"
/usr/bin/plutil -insert app_cdhash -string "$APP_CDHASH" -- "$manifest_plist"
/usr/bin/plutil -insert app_executable_sha256 -string "$APP_EXECUTABLE_SHA256" -- "$manifest_plist"
/usr/bin/plutil -insert app_certificate_sha256 -string "$APP_CERTIFICATE_SHA256" -- "$manifest_plist"
/usr/bin/plutil -insert app_designated_requirement_sha256 -string "$APP_DESIGNATED_REQUIREMENT_SHA256" -- "$manifest_plist"
/usr/bin/plutil -insert app_entitlements_sha256 -string "$APP_ENTITLEMENTS_SHA256" -- "$manifest_plist"
/usr/bin/plutil -insert scenarios -string "$scenario_list" -- "$manifest_plist"
/usr/bin/plutil -insert results_sha256 -string "$results_sha256" -- "$manifest_plist"
/usr/bin/plutil -insert screenshots_manifest -string "$screenshot_manifest" -- "$manifest_plist"
/usr/bin/plutil -insert screenshots_manifest_sha256 -string "$screenshot_manifest_sha256" -- "$manifest_plist"
/usr/bin/plutil -insert screenshot_count -integer "$screenshot_count" -- "$manifest_plist"
/usr/bin/plutil -insert created_at -string "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" -- "$manifest_plist"
/usr/bin/plutil -convert json -r -o "$manifest_json" -- "$manifest_plist"
/usr/bin/plutil -convert xml1 -o /dev/null -- "$manifest_json" >/dev/null
mv -f "$manifest_json" "$ARTIFACT_DIR/gui-run.json"
rm -f "$manifest_plist"
chmod 600 "$ARTIFACT_DIR/gui-run.json"
chmod 600 "$screenshot_manifest"
echo "screenshots: $ARTIFACT_DIR"
echo "acceptance data: $ACCEPTANCE_ROOT"
ls "$ARTIFACT_DIR" 2>/dev/null | sed 's/^/  /' || true

if [[ "$BLOCKED" == 1 ]]; then
  exit 2
fi
if [[ "$FAILED" == 1 ]]; then
  exit 1
fi
echo "UI_SMOKE_PASS"

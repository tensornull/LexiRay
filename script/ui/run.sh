#!/usr/bin/env bash
# GUI scenario runner. Builds the workspace app, seeds deterministic fixtures,
# runs each scenario as lib.swift + scenarios/<name>.swift, and stores
# screenshot evidence per run.
#
# Usage:
#   script/ui/run.sh                          # all scenarios
#   script/ui/run.sh panel_blank history_nav  # selected scenarios
#   script/ui/run.sh --skip-build ...         # reuse the existing workspace app
#   script/ui/run.sh --quit-other-copies ...  # quit non-workspace LexiRay copies
#                                             # for the run, restore them after
#   script/ui/run.sh --list
#
# Exit codes: 0 all passed, 1 at least one scenario failed, 2 blocked
# (missing permission, foreign LexiRay copy, or shielded GUI session).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
UI_DIR="$ROOT_DIR/script/ui"
SCENARIO_DIR="$UI_DIR/scenarios"
APP_BUNDLE="$ROOT_DIR/build/DerivedData/Build/Products/Debug/LexiRay.app"
LEXIRAY_HOME="$HOME/.lexiray"
PROVIDERS_FILE="$LEXIRAY_HOME/providers.json"
HISTORY_FILE="$LEXIRAY_HOME/history.json"

SCENARIO_ORDER=(launch providers settings_identity panel_blank source_editor history_nav rich_result_wrap pin selection_translate manual_resize_preserved streaming_growth)

cd "$ROOT_DIR"

usage() {
  sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

SKIP_BUILD=0
QUIT_OTHER_COPIES=0
REQUESTED=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-build) SKIP_BUILD=1 ;;
    --quit-other-copies) QUIT_OTHER_COPIES=1 ;;
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

# --- Build (or verify) the canonical workspace app.
if [[ "$SKIP_BUILD" == 1 ]]; then
  if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "UI_BLOCKED[build]: --skip-build was passed but $APP_BUNDLE does not exist" >&2
    exit 2
  fi
else
  ./script/build_and_run.sh --verify >/dev/null
fi

# --- Foreign copies (e.g. /Applications install) steal hotkeys and AX
# targeting and trip the in-app identity guard. Quit them for the test run and
# restore them afterwards when --quit-other-copies is passed; otherwise the
# scenario startup guard reports them as a blocker.
FOREIGN_BUNDLES_FILE="$(mktemp "${TMPDIR:-/tmp}/lexiray-ui-foreign.XXXXXX")"

list_foreign_copies() {
  (pgrep -x "LexiRay" || true) | while read -r pid; do
    [[ -n "$pid" ]] || continue
    args="$(ps -p "$pid" -o args=)"
    case "$args" in
      "$APP_BUNDLE"/Contents/MacOS/LexiRay*) ;;
      *LexiRay.app/Contents/MacOS/LexiRay*) echo "$pid ${args%%/Contents/MacOS/LexiRay*}" ;;
    esac
  done
}

if [[ "$QUIT_OTHER_COPIES" == 1 ]]; then
  list_foreign_copies | while read -r pid bundle; do
    echo "quitting foreign LexiRay copy: $bundle (pid $pid)"
    echo "$bundle" >>"$FOREIGN_BUNDLES_FILE"
    kill "$pid" >/dev/null 2>&1 || true
  done
  sleep 1
fi

restore_foreign_copies() {
  if [[ -s "$FOREIGN_BUNDLES_FILE" ]]; then
    sort -u "$FOREIGN_BUNDLES_FILE" | while read -r bundle; do
      [[ -d "$bundle" ]] && /usr/bin/open "$bundle" || true
    done
  fi
  rm -f "$FOREIGN_BUNDLES_FILE"
}

launchctl setenv LEXIRAY_UI_SCENARIO 1 >/dev/null 2>&1 || true

# --- Evidence directory.
RUN_STAMP="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_DIR="${LEXIRAY_UI_ARTIFACT_DIR:-$ROOT_DIR/build/ui-artifacts/$RUN_STAMP}"
mkdir -p "$ARTIFACT_DIR"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lexiray-ui.XXXXXX")"

# --- Fixtures: deterministic provider + history + defaults state, restored on
# exit. UserDefaults must be reset too: persisted panel size, hotkeys, and
# similar state otherwise leak the local machine's history into assertions.
#
# User state is backed up to a PERSISTENT directory with a .pending marker, not
# a temp dir: if a run is killed before cleanup, the next run detects the
# marker and restores the real user state instead of backing up the fixture as
# if it were user data (which would destroy the user's provider config).
STATE_BACKUP="$HOME/.lexiray-ui-backup"
PENDING_MARKER="$STATE_BACKUP/.pending"
DEFAULTS_DOMAIN="io.github.tensornull.lexiray"
LEXIRAY_HOME_EXISTED=0
[[ -d "$LEXIRAY_HOME" ]] && LEXIRAY_HOME_EXISTED=1

restore_user_state() {
  if [[ -f "$STATE_BACKUP/providers.json" ]]; then
    mkdir -p "$LEXIRAY_HOME"
    cp -p "$STATE_BACKUP/providers.json" "$PROVIDERS_FILE"
  else
    rm -f "$PROVIDERS_FILE"
  fi
  if [[ -f "$STATE_BACKUP/history.json" ]]; then
    mkdir -p "$LEXIRAY_HOME"
    cp -p "$STATE_BACKUP/history.json" "$HISTORY_FILE"
  else
    rm -f "$HISTORY_FILE"
  fi
  if [[ -f "$STATE_BACKUP/defaults.plist" ]]; then
    # Delete first: import merges into cfprefsd's cached view otherwise and
    # keys written by the test app can mask restored values.
    defaults delete "$DEFAULTS_DOMAIN" >/dev/null 2>&1 || true
    defaults import "$DEFAULTS_DOMAIN" "$STATE_BACKUP/defaults.plist" 2>/dev/null || true
  else
    defaults delete "$DEFAULTS_DOMAIN" >/dev/null 2>&1 || true
  fi
  rm -f "$PENDING_MARKER"
}

stop_workspace_app() {
  (pgrep -x "LexiRay" || true) | while read -r pid; do
    [[ -n "$pid" ]] || continue
    case "$(ps -p "$pid" -o args=)" in
      "$APP_BUNDLE"/Contents/MacOS/LexiRay*) kill "$pid" >/dev/null 2>&1 || true ;;
    esac
  done
  sleep 1
  (pgrep -x "LexiRay" || true) | while read -r pid; do
    [[ -n "$pid" ]] || continue
    case "$(ps -p "$pid" -o args=)" in
      "$APP_BUNDLE"/Contents/MacOS/LexiRay*) kill -9 "$pid" >/dev/null 2>&1 || true ;;
    esac
  done
}

seed_fixture_state() {
  stop_workspace_app
  defaults delete "$DEFAULTS_DOMAIN" >/dev/null 2>&1 || true
  mkdir -p "$LEXIRAY_HOME"
  cp "$UI_DIR/fixtures/providers.json" "$PROVIDERS_FILE"
  cp "$UI_DIR/fixtures/history.json" "$HISTORY_FILE"
  chmod 600 "$PROVIDERS_FILE" "$HISTORY_FILE"
}

cleanup() {
  stop_workspace_app
  restore_user_state
  launchctl unsetenv LEXIRAY_UI_SCENARIO >/dev/null 2>&1 || true
  if [[ "$LEXIRAY_HOME_EXISTED" == 0 ]]; then
    rmdir "$LEXIRAY_HOME" 2>/dev/null || true
  fi
  rm -rf "$WORK_DIR"
  restore_foreign_copies
}
trap cleanup EXIT

# The app must be stopped before snapshotting defaults: a live process can
# rewrite them on quit and stale state leaks into the run.
stop_workspace_app

if [[ -f "$PENDING_MARKER" ]]; then
  echo "recovering user state left behind by an interrupted run"
  restore_user_state
fi

mkdir -p "$STATE_BACKUP"
rm -f "$STATE_BACKUP/providers.json" "$STATE_BACKUP/history.json" "$STATE_BACKUP/defaults.plist"
[[ -f "$PROVIDERS_FILE" ]] && cp -p "$PROVIDERS_FILE" "$STATE_BACKUP/providers.json"
[[ -f "$HISTORY_FILE" ]] && cp -p "$HISTORY_FILE" "$STATE_BACKUP/history.json"
defaults export "$DEFAULTS_DOMAIN" "$STATE_BACKUP/defaults.plist" 2>/dev/null || true
touch "$PENDING_MARKER"

# --- Run scenarios.
declare -a RESULTS=()
FAILED=0
BLOCKED=0

for name in "${REQUESTED[@]}"; do
  seed_fixture_state
  echo "--- scenario: $name"
  set +e
  cat "$UI_DIR/lib.swift" "$SCENARIO_DIR/$name.swift" |
    swift - "$APP_BUNDLE" "$WORK_DIR" "$ARTIFACT_DIR" "$name" "$ROOT_DIR"
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
echo "screenshots: $ARTIFACT_DIR"
ls "$ARTIFACT_DIR" 2>/dev/null | sed 's/^/  /' || true

if [[ "$BLOCKED" == 1 ]]; then
  exit 2
fi
if [[ "$FAILED" == 1 ]]; then
  exit 1
fi
echo "UI_SMOKE_PASS"

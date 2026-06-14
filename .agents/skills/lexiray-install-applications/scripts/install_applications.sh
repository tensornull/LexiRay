#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
APP_NAME="LexiRay"
SIGN_IDENTITY="${LEXIRAY_CODE_SIGN_IDENTITY:-LexiRay Local Development}"
APP_SRC="$ROOT_DIR/build/DerivedData/Build/Products/Debug/$APP_NAME.app"
APP_DST="/Applications/$APP_NAME.app"
APP_TMP="/Applications/$APP_NAME.app.codex-installing"
BACKUP_PATH=""

require_repo() {
  if [[ ! -f "$ROOT_DIR/LexiRay.xcodeproj/project.pbxproj" && ! -f "$ROOT_DIR/project.yml" ]]; then
    echo "This helper must run from the LexiRay repository." >&2
    echo "Resolved root: $ROOT_DIR" >&2
    exit 2
  fi
}

kill_lexiray_apps() {
  (pgrep -x "$APP_NAME" || true) | while read -r pid; do
    [[ -n "$pid" ]] || continue
    local args
    args="$(ps -p "$pid" -o args= 2>/dev/null || true)"
    case "$args" in
      *"$APP_NAME.app/Contents/MacOS/$APP_NAME"*) kill "$pid" >/dev/null 2>&1 || true ;;
    esac
  done

  sleep 1

  (pgrep -x "$APP_NAME" || true) | while read -r pid; do
    [[ -n "$pid" ]] || continue
    local args
    args="$(ps -p "$pid" -o args= 2>/dev/null || true)"
    case "$args" in
      *"$APP_NAME.app/Contents/MacOS/$APP_NAME"*) kill -9 "$pid" >/dev/null 2>&1 || true ;;
    esac
  done
}

verify_signature() {
  local bundle="$1"
  /usr/bin/codesign --verify --deep --strict "$bundle"
  if ! /usr/bin/codesign -dvvv "$bundle" 2>&1 | /usr/bin/grep -F "Authority=$SIGN_IDENTITY" >/dev/null; then
    echo "Expected $bundle to be signed by \"$SIGN_IDENTITY\"." >&2
    /usr/bin/codesign -dvvv "$bundle" 2>&1 >&2
    exit 1
  fi
}

restore_backup_if_needed() {
  if [[ -n "$BACKUP_PATH" && -d "$BACKUP_PATH" && ! -d "$APP_DST" ]]; then
    mv "$BACKUP_PATH" "$APP_DST" || true
  fi
}

cleanup_tmp() {
  rm -rf "$APP_TMP"
}

trap 'restore_backup_if_needed; cleanup_tmp' EXIT

require_repo
cd "$ROOT_DIR"

./script/build_and_run.sh --verify

if [[ ! -d "$APP_SRC" ]]; then
  echo "Workspace build did not produce $APP_SRC." >&2
  exit 1
fi

rm -rf "$APP_TMP"
/usr/bin/ditto "$APP_SRC" "$APP_TMP"
verify_signature "$APP_TMP"

kill_lexiray_apps

if [[ -d "$APP_DST" ]]; then
  BACKUP_PATH="/Applications/$APP_NAME.app.codex-backup-$(date +%Y%m%d-%H%M%S)"
  mv "$APP_DST" "$BACKUP_PATH"
fi

mv "$APP_TMP" "$APP_DST"

if [[ -n "$BACKUP_PATH" && -d "$BACKUP_PATH" ]]; then
  rm -rf "$BACKUP_PATH"
  BACKUP_PATH=""
fi

/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister \
  -f -R -trusted "$APP_DST"
verify_signature "$APP_DST"

/usr/bin/open -n "$APP_DST"
sleep 2

(pgrep -x "$APP_NAME" || true) | while read -r pid; do
  [[ -n "$pid" ]] || continue
  args="$(ps -p "$pid" -o args= 2>/dev/null || true)"
  case "$args" in
    "$APP_DST/Contents/MacOS/$APP_NAME"*)
      echo "RUNNING_PID=$pid"
      echo "RUNNING_PATH=$APP_DST/Contents/MacOS/$APP_NAME"
      ;;
  esac
done | tee /tmp/lexiray-applications-install-running.txt

if ! /usr/bin/grep -F "RUNNING_PATH=$APP_DST/Contents/MacOS/$APP_NAME" /tmp/lexiray-applications-install-running.txt >/dev/null; then
  echo "Installed app did not appear to launch from $APP_DST." >&2
  exit 1
fi

echo "INSTALLED=$APP_DST"
/usr/bin/codesign -dvvv "$APP_DST" 2>&1 | sed -n '1,35p'

#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="LexiRay"
BUNDLE_ID="io.github.tensornull.lexiray"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/build/DerivedData"
PROJECT="$ROOT_DIR/LexiRay.xcodeproj"
BUILT_APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"
# The build product is installed into /Applications so local testing and any
# later launch (Spotlight, Launchpad, after a reboot) always resolve to the
# same app. Everything downstream — signature check, process management, open —
# targets the installed copy, never the DerivedData build directory.
INSTALLED_APP_BUNDLE="/Applications/$APP_NAME.app"
APP_BUNDLE="$INSTALLED_APP_BUNDLE"
APP_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
CODE_SIGN_IDENTITY="${LEXIRAY_CODE_SIGN_IDENTITY:-LexiRay Local Development}"

cd "$ROOT_DIR"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required. Install with: brew install xcodegen" >&2
  exit 127
fi

is_development_process() {
  local process_path="$1"
  case "$process_path" in
    "$INSTALLED_APP_BUNDLE"/Contents/MacOS/"$APP_NAME"*) return 0 ;;
    "$ROOT_DIR"/build/*/"$APP_NAME.app"/Contents/MacOS/"$APP_NAME"*) return 0 ;;
    "$HOME"/Library/Developer/Xcode/DerivedData/"$APP_NAME"-*/Build/Products/*/"$APP_NAME.app"/Contents/MacOS/"$APP_NAME"*) return 0 ;;
    *) return 1 ;;
  esac
}

kill_development_apps() {
  (pgrep -x "$APP_NAME" || true) | while read -r pid; do
    [[ -n "$pid" ]] || continue
    process_path="$(ps -p "$pid" -o args=)"
    if is_development_process "$process_path"; then
      kill "$pid" >/dev/null 2>&1 || true
    fi
  done

  sleep 1

  (pgrep -x "$APP_NAME" || true) | while read -r pid; do
    [[ -n "$pid" ]] || continue
    process_path="$(ps -p "$pid" -o args=)"
    if is_development_process "$process_path"; then
      kill -9 "$pid" >/dev/null 2>&1 || true
    fi
  done
}

keep_only_workspace_app() {
  (pgrep -x "$APP_NAME" || true) | while read -r pid; do
    [[ -n "$pid" ]] || continue
    process_path="$(ps -p "$pid" -o args=)"
    case "$process_path" in
      "$APP_BUNDLE"/Contents/MacOS/"$APP_NAME") ;;
      *)
        if is_development_process "$process_path"; then
          kill "$pid" >/dev/null 2>&1 || true
        fi
        ;;
    esac
  done

  sleep 1

  (pgrep -x "$APP_NAME" || true) | while read -r pid; do
    [[ -n "$pid" ]] || continue
    process_path="$(ps -p "$pid" -o args=)"
    case "$process_path" in
      "$APP_BUNDLE"/Contents/MacOS/"$APP_NAME") ;;
      *)
        if is_development_process "$process_path"; then
          kill -9 "$pid" >/dev/null 2>&1 || true
        fi
        ;;
    esac
  done
}

canonical_app_is_running() {
  (pgrep -x "$APP_NAME" || true) | while read -r pid; do
    [[ -n "$pid" ]] || continue
    process_path="$(ps -p "$pid" -o args=)"
    case "$process_path" in
      "$APP_EXECUTABLE"*) echo "$pid" ;;
    esac
  done
}

verify_app_signature() {
  local bundle="$1"
  local signature
  signature="$(/usr/bin/codesign -dvvv "$bundle" 2>&1)"

  if /usr/bin/grep -F "Signature=adhoc" <<<"$signature" >/dev/null ||
    ! /usr/bin/grep -F "Authority=$CODE_SIGN_IDENTITY" <<<"$signature" >/dev/null; then
    echo "Expected $bundle to be signed by \"$CODE_SIGN_IDENTITY\"." >&2
    echo "$signature" >&2
    exit 1
  fi
}

# Replace /Applications/LexiRay.app with the freshly built bundle so that every
# subsequent launch — including from Spotlight/Launchpad after a reboot —
# resolves to exactly what was just built and tested.
install_to_applications() {
  rm -rf "$INSTALLED_APP_BUNDLE"
  /bin/cp -R "$BUILT_APP_BUNDLE" "$INSTALLED_APP_BUNDLE"
  # Refresh Launch Services so the new bundle wins Spotlight/Launchpad lookups.
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$INSTALLED_APP_BUNDLE" >/dev/null 2>&1 || true
}

kill_development_apps
"$ROOT_DIR/script/clean_dev_apps.sh" --apply
rm -rf "$BUILT_APP_BUNDLE"
"$ROOT_DIR/script/ensure_local_codesign_identity.sh" "$CODE_SIGN_IDENTITY"

xcodegen generate
xcodebuild \
  -project "$PROJECT" \
  -scheme "$APP_NAME" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY" \
  DEVELOPMENT_TEAM= \
  ENABLE_DEBUG_DYLIB=NO \
  build
verify_app_signature "$BUILT_APP_BUNDLE"

# Nothing may hold the installed bundle open while we replace it.
kill_development_apps
install_to_applications
verify_app_signature "$INSTALLED_APP_BUNDLE"

open_app() {
  if [[ -n "$(canonical_app_is_running)" ]]; then
    /usr/bin/open "$APP_BUNDLE"
    return
  fi

  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    [[ -n "$(canonical_app_is_running)" ]]
    keep_only_workspace_app
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac

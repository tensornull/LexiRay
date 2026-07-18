#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="LexiRay"
BUNDLE_ID="io.github.tensornull.lexiray"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/development_identity.sh"
DERIVED_DATA="$ROOT_DIR/build/DerivedData"
PROJECT="$ROOT_DIR/LexiRay.xcodeproj"
BUILT_APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"
BUILD_FINGERPRINT_FILE="$BUILT_APP_BUNDLE.source-fingerprint"
# Development builds and launches always use the canonical workspace bundle.
# Installing into /Applications is a separate, receipt-gated workflow.
APP_BUNDLE="$BUILT_APP_BUNDLE"
APP_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
CODE_SIGN_IDENTITY="$LEXIRAY_DEVELOPMENT_CERT_SHA1"
SOURCE_FINGERPRINT_BEFORE="$("$ROOT_DIR/script/acceptance_receipt.sh" fingerprint)"

cd "$ROOT_DIR"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required. Install with: brew install xcodegen" >&2
  exit 127
fi

is_development_process() {
  local process_path="$1"
  case "$process_path" in
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
  if ! lexiray_verify_development_app_identity "$bundle"; then
    echo "Expected $bundle to use the fixed LexiRay development identity." >&2
    /usr/bin/codesign -dvvv "$bundle" 2>&1 || true
    exit 1
  fi
}

kill_development_apps
"$ROOT_DIR/script/clean_dev_apps.sh" --apply
rm -rf "$BUILT_APP_BUNDLE"
rm -f "$BUILD_FINGERPRINT_FILE"
"$ROOT_DIR/script/ensure_local_codesign_identity.sh"

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
SOURCE_FINGERPRINT_AFTER="$("$ROOT_DIR/script/acceptance_receipt.sh" fingerprint)"
if [[ "$SOURCE_FINGERPRINT_AFTER" != "$SOURCE_FINGERPRINT_BEFORE" ]]; then
  echo "Source inputs changed during the workspace build; refusing to attest the app." >&2
  exit 1
fi
printf '%s\n' "$SOURCE_FINGERPRINT_AFTER" >"$BUILD_FINGERPRINT_FILE.tmp"
mv -f "$BUILD_FINGERPRINT_FILE.tmp" "$BUILD_FINGERPRINT_FILE"

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
  --build|build|--verify|verify)
    # Build/signature verification is deliberately launch-free. Automated UI
    # flows launch only after installing their isolated acceptance profile.
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--build|--verify]" >&2
    exit 2
    ;;
esac

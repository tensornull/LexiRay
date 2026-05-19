#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="LexiRay"
BUNDLE_ID="io.github.tensornull.lexiray"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/build/DerivedData"
PROJECT="$ROOT_DIR/LexiRay.xcodeproj"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"

cd "$ROOT_DIR"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required. Install with: brew install xcodegen" >&2
  exit 127
fi

kill_existing_app() {
  (pgrep -x "$APP_NAME" || true) | while read -r pid; do
    [[ -n "$pid" ]] || continue
    kill "$pid" >/dev/null 2>&1 || true
  done

  sleep 1

  (pgrep -x "$APP_NAME" || true) | while read -r pid; do
    [[ -n "$pid" ]] || continue
    kill -9 "$pid" >/dev/null 2>&1 || true
  done
}

keep_only_workspace_app() {
  (pgrep -x "$APP_NAME" || true) | while read -r pid; do
    [[ -n "$pid" ]] || continue
    process_path="$(ps -p "$pid" -o args=)"
    case "$process_path" in
      "$APP_BUNDLE"/Contents/MacOS/"$APP_NAME") ;;
      *) kill "$pid" >/dev/null 2>&1 || true ;;
    esac
  done

  sleep 1

  (pgrep -x "$APP_NAME" || true) | while read -r pid; do
    [[ -n "$pid" ]] || continue
    process_path="$(ps -p "$pid" -o args=)"
    case "$process_path" in
      "$APP_BUNDLE"/Contents/MacOS/"$APP_NAME") ;;
      *) kill -9 "$pid" >/dev/null 2>&1 || true ;;
    esac
  done
}

kill_existing_app

xcodegen generate
xcodebuild \
  -project "$PROJECT" \
  -scheme "$APP_NAME" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build

open_app() {
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
    pgrep -x "$APP_NAME" >/dev/null
    keep_only_workspace_app
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac

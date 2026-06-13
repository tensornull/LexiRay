#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <path-to-LexiRay.app>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$1"
IDENTITY_NAME="${LEXIRAY_RELEASE_CODE_SIGN_IDENTITY:-LexiRay Release Self-Signed}"
ENTITLEMENTS_PATH="$ROOT_DIR/LexiRay/Resources/LexiRay.entitlements"
EXPECTED_BUNDLE_ID="io.github.tensornull.lexiray"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 1
fi

if [[ ! -f "$APP_PATH/Contents/Info.plist" ]]; then
  echo "Info.plist not found in app bundle: $APP_PATH" >&2
  exit 1
fi

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist")"
if [[ "$bundle_id" != "$EXPECTED_BUNDLE_ID" ]]; then
  echo "Unexpected bundle identifier: $bundle_id, expected $EXPECTED_BUNDLE_ID." >&2
  exit 1
fi

/usr/bin/codesign \
  --force \
  --options runtime \
  --timestamp=none \
  --entitlements "$ENTITLEMENTS_PATH" \
  --sign "$IDENTITY_NAME" \
  "$APP_PATH"

/usr/bin/codesign --verify --deep --strict --verbose=4 "$APP_PATH"
signature="$(/usr/bin/codesign -dvvv "$APP_PATH" 2>&1)"

if /usr/bin/grep -F "Signature=adhoc" <<<"$signature" >/dev/null; then
  echo "Release app is still ad hoc signed." >&2
  echo "$signature" >&2
  exit 1
fi

if ! /usr/bin/grep -F "Authority=$IDENTITY_NAME" <<<"$signature" >/dev/null; then
  echo "Release app was not signed by \"$IDENTITY_NAME\"." >&2
  echo "$signature" >&2
  exit 1
fi

if ! /usr/bin/grep -F "Identifier=$EXPECTED_BUNDLE_ID" <<<"$signature" >/dev/null; then
  echo "Release app signature does not bind the expected bundle identifier." >&2
  echo "$signature" >&2
  exit 1
fi

if /usr/bin/grep -F "Info.plist=not bound" <<<"$signature" >/dev/null ||
  ! /usr/bin/grep -F "Info.plist entries=" <<<"$signature" >/dev/null; then
  echo "Release app signature does not bind Info.plist." >&2
  echo "$signature" >&2
  exit 1
fi

if /usr/bin/grep -F "Sealed Resources=none" <<<"$signature" >/dev/null ||
  ! /usr/bin/grep -F "Sealed Resources version=" <<<"$signature" >/dev/null; then
  echo "Release app resources are not sealed." >&2
  echo "$signature" >&2
  exit 1
fi

echo "$signature"
echo "Signed release app: $APP_PATH"

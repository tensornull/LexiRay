#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: $0 <path-to-dmg> [expected-version]" >&2
  exit 2
fi

DMG_PATH="$1"
EXPECTED_VERSION="${2:-}"
EXPECTED_BUNDLE_ID="io.github.tensornull.lexiray"
MOUNT_ROOT="$(/usr/bin/mktemp -d)"
MOUNT_POINT="$MOUNT_ROOT/mnt"

cleanup() {
  if /sbin/mount | /usr/bin/grep -F "$MOUNT_POINT" >/dev/null 2>&1; then
    /usr/bin/hdiutil detach "$MOUNT_POINT" -quiet || true
  fi
  rm -rf "$MOUNT_ROOT"
}
trap cleanup EXIT

if [[ ! -f "$DMG_PATH" ]]; then
  echo "DMG not found: $DMG_PATH" >&2
  exit 1
fi

/usr/bin/hdiutil verify "$DMG_PATH"
mkdir "$MOUNT_POINT"
/usr/bin/hdiutil attach "$DMG_PATH" -nobrowse -readonly -mountpoint "$MOUNT_POINT" -quiet

APP_PATH="$MOUNT_POINT/LexiRay.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "LexiRay.app not found at DMG root." >&2
  find "$MOUNT_POINT" -maxdepth 2 -print >&2
  exit 1
fi

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist")"
if [[ "$bundle_id" != "$EXPECTED_BUNDLE_ID" ]]; then
  echo "Unexpected bundle identifier in DMG app: $bundle_id, expected $EXPECTED_BUNDLE_ID." >&2
  exit 1
fi

if [[ -n "$EXPECTED_VERSION" ]]; then
  app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
  if [[ "$app_version" != "$EXPECTED_VERSION" ]]; then
    echo "Unexpected app version in DMG: $app_version, expected $EXPECTED_VERSION." >&2
    exit 1
  fi
fi

/usr/bin/codesign --verify --deep --strict --verbose=4 "$APP_PATH"
signature="$(/usr/bin/codesign -dvvv "$APP_PATH" 2>&1)"

if /usr/bin/grep -F "Signature=adhoc" <<<"$signature" >/dev/null ||
  ! /usr/bin/grep -F "Authority=" <<<"$signature" >/dev/null; then
  echo "DMG app does not have a usable release signature." >&2
  echo "$signature" >&2
  exit 1
fi

if ! /usr/bin/grep -F "Identifier=$EXPECTED_BUNDLE_ID" <<<"$signature" >/dev/null; then
  echo "DMG app signature does not bind the expected bundle identifier." >&2
  echo "$signature" >&2
  exit 1
fi

if /usr/bin/grep -F "Info.plist=not bound" <<<"$signature" >/dev/null ||
  ! /usr/bin/grep -F "Info.plist entries=" <<<"$signature" >/dev/null; then
  echo "DMG app signature does not bind Info.plist." >&2
  echo "$signature" >&2
  exit 1
fi

if /usr/bin/grep -F "Sealed Resources=none" <<<"$signature" >/dev/null ||
  ! /usr/bin/grep -F "Sealed Resources version=" <<<"$signature" >/dev/null; then
  echo "DMG app resources are not sealed." >&2
  echo "$signature" >&2
  exit 1
fi

spctl_output="$(/usr/sbin/spctl -a -vv "$APP_PATH" 2>&1 || true)"
if /usr/bin/grep -E "no usable signature|code object is not signed" <<<"$spctl_output" >/dev/null; then
  echo "Gatekeeper reported a missing or unusable signature." >&2
  echo "$spctl_output" >&2
  exit 1
fi

echo "$signature"
echo "$spctl_output"
echo "Verified release DMG: $DMG_PATH"

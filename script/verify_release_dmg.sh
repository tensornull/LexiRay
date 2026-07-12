#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 5 ]]; then
  echo "usage: $0 <path-to-dmg> [expected-version] [expected-build] [expected-commit] [expected-fingerprint]" >&2
  exit 2
fi

DMG_PATH="$1"
EXPECTED_VERSION="${2:-}"
EXPECTED_BUILD="${3:-}"
EXPECTED_COMMIT="${4:-}"
EXPECTED_FINGERPRINT="${5:-}"
EXPECTED_BUNDLE_ID="io.github.tensornull.lexiray"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=release_identity.sh
source "$ROOT_DIR/script/release_identity.sh"
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
if [[ ! -d "$APP_PATH" || -L "$APP_PATH" ]]; then
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

if [[ -n "$EXPECTED_BUILD" ]]; then
  app_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist")"
  if [[ "$app_build" != "$EXPECTED_BUILD" ]]; then
    echo "Unexpected app build in DMG: $app_build, expected $EXPECTED_BUILD." >&2
    exit 1
  fi
fi

if [[ -n "$EXPECTED_COMMIT" || -n "$EXPECTED_FINGERPRINT" ]]; then
  ATTESTATION_PATH="$APP_PATH/Contents/Resources/LexiRayRelease.plist"
  [[ -f "$ATTESTATION_PATH" ]] || { echo "Release source attestation is missing." >&2; exit 1; }
  attested_commit="$(/usr/libexec/PlistBuddy -c 'Print :source_commit' "$ATTESTATION_PATH")"
  attested_fingerprint="$(/usr/libexec/PlistBuddy -c 'Print :source_fingerprint' "$ATTESTATION_PATH")"
  [[ "$attested_commit" == "$EXPECTED_COMMIT" ]] || { echo "Release source commit attestation mismatch." >&2; exit 1; }
  [[ "$attested_fingerprint" == "$EXPECTED_FINGERPRINT" ]] || { echo "Release source fingerprint attestation mismatch." >&2; exit 1; }
fi

/usr/bin/codesign --verify --deep --strict --verbose=4 "$APP_PATH"
signature="$(/usr/bin/codesign -dvvv "$APP_PATH" 2>&1)"

if /usr/bin/grep -F "Signature=adhoc" <<<"$signature" >/dev/null ||
  ! /usr/bin/grep -F "Authority=" <<<"$signature" >/dev/null; then
  echo "DMG app does not have a usable release signature." >&2
  echo "$signature" >&2
  exit 1
fi

if ! /usr/bin/grep -F "Authority=$LEXIRAY_RELEASE_IDENTITY_NAME" <<<"$signature" >/dev/null; then
  echo "DMG app was not signed by the fixed release identity." >&2
  echo "$signature" >&2
  exit 1
fi

certificate_fingerprint="$(lexiray_app_certificate_sha256 "$APP_PATH" || true)"
if [[ "$certificate_fingerprint" != "$LEXIRAY_RELEASE_CERT_SHA256" ]]; then
  echo "DMG app certificate fingerprint does not match the latest published release identity." >&2
  echo "actual: ${certificate_fingerprint:-unavailable}" >&2
  echo "expected: $LEXIRAY_RELEASE_CERT_SHA256" >&2
  exit 1
fi

if ! lexiray_verify_release_app_identity "$APP_PATH" "$ROOT_DIR/LexiRay/Resources/LexiRay.entitlements"; then
  echo "DMG app designated requirement or entitlements do not match the fixed release contract." >&2
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

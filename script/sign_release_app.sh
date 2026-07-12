#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <path-to-LexiRay.app>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=release_identity.sh
source "$ROOT_DIR/script/release_identity.sh"
# shellcheck source=release_capability.sh
source "$ROOT_DIR/script/release_capability.sh"
APP_PATH="$1"
IDENTITY_NAME="$LEXIRAY_RELEASE_IDENTITY_NAME"
KEYCHAIN_PATH="${LEXIRAY_RELEASE_KEYCHAIN_PATH:-}"
ENTITLEMENTS_PATH="$ROOT_DIR/LexiRay/Resources/LexiRay.entitlements"
EXPECTED_BUNDLE_ID="io.github.tensornull.lexiray"

if [[ "${LEXIRAY_RELEASE_NO_UI:-}" != 1 ]]; then
  echo "Release signing requires the noninteractive release orchestrator." >&2
  exit 1
fi
release_mode="${LEXIRAY_RELEASE_ORCHESTRATED:-}"
case "$release_mode" in
  local|fallback-build) ;;
  *) echo "Direct release signing is disabled. Use script/release.sh publish." >&2; exit 1 ;;
esac
[[ "$APP_PATH" == "$ROOT_DIR/build/release/LexiRay.app" ]] || {
  echo "Release signing is restricted to the canonical release app path." >&2
  exit 1
}
if [[ "$release_mode" == local ]]; then
  lexiray_require_release_capability "$ROOT_DIR" \
    "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/LexiRay/Resources/Info.plist")" \
    local || {
    echo "Release signing requires a live, locked release.sh capability." >&2
    exit 1
  }
else
  source_commit="${LEXIRAY_RELEASE_SOURCE_COMMIT:-}"
  lexiray_require_github_fallback_context "$source_commit" || {
    echo "Fallback signing is restricted to the canonical workflow_dispatch runner." >&2
    exit 1
  }
  case "$KEYCHAIN_PATH" in
    "${RUNNER_TEMP:-/__missing_runner_temp__}"/*) ;;
    *) echo "Fallback signing keychain must live under RUNNER_TEMP." >&2; exit 1 ;;
  esac
fi

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

if [[ -n "$KEYCHAIN_PATH" && ! -f "$KEYCHAIN_PATH" ]]; then
  echo "Release signing keychain not found: $KEYCHAIN_PATH" >&2
  echo "Use the one-time Keychain Access import locally, or the GitHub fallback import on an ephemeral runner." >&2
  exit 1
fi

codesign_args=(
  --force \
  --options runtime \
  --timestamp=none \
  --entitlements "$ENTITLEMENTS_PATH" \
  --sign "$LEXIRAY_RELEASE_CERT_SHA1"
)
if [[ -n "$KEYCHAIN_PATH" ]]; then
  codesign_args+=(--keychain "$KEYCHAIN_PATH")
fi
codesign_args+=("$APP_PATH")

# This is the last operation before codesign and fails rather than allowing an
# authentication dialog. The orchestrator can then resume through fallback.
if ! /usr/bin/swift "$ROOT_DIR/script/probe_release_signing_identity.swift" \
  "$IDENTITY_NAME" "$LEXIRAY_RELEASE_CERT_SHA256" >/dev/null 2>&1; then
  echo "Fixed release signing key is not usable with authentication UI disabled." >&2
  exit 1
fi
/usr/bin/codesign "${codesign_args[@]}"

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

certificate_fingerprint="$(lexiray_app_certificate_sha256 "$APP_PATH" || true)"
if [[ "$certificate_fingerprint" != "$LEXIRAY_RELEASE_CERT_SHA256" ]]; then
  echo "Release app certificate fingerprint is not the fixed published identity." >&2
  echo "actual: ${certificate_fingerprint:-unavailable}" >&2
  echo "expected: $LEXIRAY_RELEASE_CERT_SHA256" >&2
  exit 1
fi

if ! lexiray_verify_release_app_identity "$APP_PATH" "$ENTITLEMENTS_PATH"; then
  echo "Release app designated requirement or entitlements do not match the fixed release contract." >&2
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

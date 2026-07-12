#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <version-without-v>" >&2
  exit 2
fi

VERSION="$1"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=release_identity.sh
source "$ROOT_DIR/script/release_identity.sh"
# shellcheck source=release_capability.sh
source "$ROOT_DIR/script/release_capability.sh"
APP_PATH="$ROOT_DIR/build/release/LexiRay.app"
DMG_PATH="$ROOT_DIR/build/LexiRay-$VERSION.dmg"
SHA_PATH="$ROOT_DIR/build/LexiRay-$VERSION.dmg.sha256"
ATTESTATION_PATH="$APP_PATH/Contents/Resources/LexiRayRelease.plist"
IDENTITY_NAME="$LEXIRAY_RELEASE_IDENTITY_NAME"
IMPORT_KEYCHAIN="${LEXIRAY_RELEASE_KEYCHAIN_PATH:-${RUNNER_TEMP:-$ROOT_DIR/build}/lexiray-release-signing.keychain-db}"
IMPORTED_EPHEMERAL_KEYCHAIN=0

cleanup_ephemeral_keychain() {
  local keychain
  local -a retained=()

  [[ "$IMPORTED_EPHEMERAL_KEYCHAIN" -eq 1 ]] || return 0
  while IFS= read -r keychain; do
    keychain="$(/usr/bin/sed -E 's/^[[:space:]]*"//; s/"[[:space:]]*$//' <<<"$keychain")"
    [[ -n "$keychain" && "$keychain" != "$IMPORT_KEYCHAIN" ]] && retained+=("$keychain")
  done < <(/usr/bin/security list-keychains -d user 2>/dev/null || true)
  /usr/bin/security list-keychains -d user -s "${retained[@]}" >/dev/null 2>&1 || true
  /bin/rm -f "$IMPORT_KEYCHAIN"
}
trap cleanup_ephemeral_keychain EXIT

if ! lexiray_validate_release_version "$VERSION"; then
  echo "Invalid version. Pass a version without v, for example: $0 0.4.1" >&2
  exit 2
fi

if [[ "${LEXIRAY_RELEASE_NO_UI:-}" != 1 ]]; then
  echo "Release packaging requires the noninteractive release orchestrator." >&2
  exit 1
fi
release_mode="${LEXIRAY_RELEASE_ORCHESTRATED:-}"
case "$release_mode" in
  local|fallback-build) ;;
  *) echo "Direct release packaging is disabled. Use script/release.sh publish." >&2; exit 1 ;;
esac

cd "$ROOT_DIR"
if [[ "$release_mode" == local ]]; then
  lexiray_require_release_capability "$ROOT_DIR" "$VERSION" local || {
    echo "Release packaging requires a live, locked release.sh capability." >&2
    exit 1
  }
  source_commit="$LEXIRAY_VALIDATED_RELEASE_SOURCE_COMMIT"
else
  source_commit="${LEXIRAY_RELEASE_SOURCE_COMMIT:-}"
  lexiray_require_github_fallback_context "$source_commit" || {
    echo "Fallback packaging is restricted to the canonical workflow_dispatch runner." >&2
    exit 1
  }
  [[ -n "${LEXIRAY_RELEASE_CERT_P12_BASE64:-}" && -n "${LEXIRAY_RELEASE_CERT_PASSWORD:-}" ]] || {
    echo "Fallback packaging requires the fixed P12 repository secrets." >&2
    exit 1
  }
fi
[[ "$(git rev-parse HEAD)" == "$source_commit" ]] || {
  echo "Release package checkout no longer matches the authorized source commit." >&2
  exit 1
}
[[ -z "$(git status --porcelain --untracked-files=all)" ]] || {
  echo "Release package worktree must remain clean." >&2
  exit 1
}

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required. Install with: brew install xcodegen" >&2
  exit 127
fi

rm -rf "$APP_PATH" "$DMG_PATH" "$SHA_PATH"
xcodegen generate

xcodebuild build \
  -project "$ROOT_DIR/LexiRay.xcodeproj" \
  -scheme LexiRay \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$ROOT_DIR/build/DerivedData" \
  CONFIGURATION_BUILD_DIR="$ROOT_DIR/build/release" \
  CODE_SIGNING_ALLOWED=NO \
  SWIFT_COMPILATION_MODE=wholemodule

app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
app_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist")"
if [[ "$app_version" != "$VERSION" ]]; then
  echo "Unexpected app version: $app_version, expected $VERSION." >&2
  exit 1
fi
if ! [[ "$app_build" =~ ^[0-9]+$ ]] || [[ "$app_build" -lt 1 ]]; then
  echo "Release app build must be a positive integer, got: $app_build" >&2
  exit 1
fi

source_fingerprint="${LEXIRAY_RELEASE_SOURCE_FINGERPRINT:-$("$ROOT_DIR/script/acceptance_receipt.sh" fingerprint)}"
actual_source_fingerprint="$("$ROOT_DIR/script/acceptance_receipt.sh" fingerprint)"
[[ "$source_commit" =~ ^[0-9a-f]{40}$ ]] || { echo "Invalid release source commit." >&2; exit 1; }
[[ "$source_fingerprint" =~ ^[0-9a-f]{64}$ ]] || { echo "Invalid release source fingerprint." >&2; exit 1; }
[[ "$actual_source_fingerprint" == "$source_fingerprint" ]] || {
  echo "Release source changed after authorization; refusing to sign the build." >&2
  exit 1
}
/usr/bin/plutil -create xml1 "$ATTESTATION_PATH"
/usr/bin/plutil -insert source_commit -string "$source_commit" -- "$ATTESTATION_PATH"
/usr/bin/plutil -insert source_fingerprint -string "$source_fingerprint" -- "$ATTESTATION_PATH"
/usr/bin/plutil -insert version -string "$VERSION" -- "$ATTESTATION_PATH"
/usr/bin/plutil -insert build -string "$app_build" -- "$ATTESTATION_PATH"

if [[ "$release_mode" == local ]]; then
  identities="$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null || true)"
  if ! /usr/bin/grep -E "[[:space:]]$LEXIRAY_RELEASE_CERT_SHA1[[:space:]]+\"$IDENTITY_NAME\"" <<<"$identities" >/dev/null ||
    ! lexiray_has_fixed_release_certificate; then
    echo "Fixed release identity \"$IDENTITY_NAME\" is no longer accessible." >&2
    echo "Resume through script/release.sh so it can select the GitHub fallback." >&2
    exit 1
  fi
  # A one-time, user-managed import is the normal local path. Do not unlock or
  # rewrite any keychain during packaging.
  unset LEXIRAY_RELEASE_KEYCHAIN_PATH
else
  # The GitHub fallback receives both values from repository secrets and uses
  # an ephemeral runner keychain. Local release.sh never supplies these values.
  export LEXIRAY_RELEASE_KEYCHAIN_PATH="$IMPORT_KEYCHAIN"
  IMPORTED_EPHEMERAL_KEYCHAIN=1
  "$ROOT_DIR/script/import_release_signing_identity.sh"
  unset LEXIRAY_RELEASE_CERT_P12_BASE64
  unset LEXIRAY_RELEASE_CERT_PASSWORD
  unset LEXIRAY_RELEASE_KEYCHAIN_PASSWORD
fi
"$ROOT_DIR/script/sign_release_app.sh" "$APP_PATH"

/usr/bin/hdiutil create -volname "LexiRay" -srcfolder "$APP_PATH" -ov -format UDZO "$DMG_PATH"
"$ROOT_DIR/script/verify_release_dmg.sh" \
  "$DMG_PATH" "$VERSION" "$app_build" "$source_commit" "$source_fingerprint"
(cd "$ROOT_DIR/build" && /usr/bin/shasum -a 256 "LexiRay-$VERSION.dmg" >"LexiRay-$VERSION.dmg.sha256")
test -s "$SHA_PATH"

echo "Packaged signed release DMG: $DMG_PATH"
echo "SHA-256: $SHA_PATH"

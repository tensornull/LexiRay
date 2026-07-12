#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=release_identity.sh
source "$ROOT_DIR/script/release_identity.sh"
MARKER="$ROOT_DIR/build/release-state/local-signing-ready.plist"
WORK_DIR="$(/usr/bin/mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

identities="$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null || true)"
/usr/bin/grep -E "[[:space:]]$LEXIRAY_RELEASE_CERT_SHA1[[:space:]]+\"$LEXIRAY_RELEASE_IDENTITY_NAME\"" <<<"$identities" >/dev/null &&
  lexiray_has_fixed_release_certificate || {
    echo "The exact fixed release identity is not available in the user keychain search list." >&2
    exit 1
  }

echo "Running the one-time signing ACL probe. This command is never called by release doctor." >&2
echo "If macOS asks for key access, configure /usr/bin/codesign as Always Allow; do not enter a stale keychain password." >&2
/bin/cp /usr/bin/true "$WORK_DIR/probe"
/usr/bin/codesign --force --timestamp=none --sign "$LEXIRAY_RELEASE_CERT_SHA1" "$WORK_DIR/probe"
/usr/bin/codesign --verify --strict "$WORK_DIR/probe"
[[ "$(lexiray_app_certificate_sha256 "$WORK_DIR/probe")" == "$LEXIRAY_RELEASE_CERT_SHA256" ]]

mkdir -p "$(dirname "$MARKER")"
/usr/bin/plutil -create xml1 "$MARKER"
/usr/bin/plutil -insert certificate_sha256 -string "$LEXIRAY_RELEASE_CERT_SHA256" -- "$MARKER"
/usr/bin/plutil -insert codesign_path -string /usr/bin/codesign -- "$MARKER"
/usr/bin/plutil -insert result -string passed -- "$MARKER"
/usr/bin/plutil -insert verified_at -string "$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)" -- "$MARKER"
chmod 600 "$MARKER"
echo "Local release signing readiness recorded: $MARKER"

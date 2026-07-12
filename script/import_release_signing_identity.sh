#!/usr/bin/env bash
set -euo pipefail
umask 077

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=release_identity.sh
source "$ROOT_DIR/script/release_identity.sh"
# shellcheck source=release_capability.sh
source "$ROOT_DIR/script/release_capability.sh"
IDENTITY_NAME="$LEXIRAY_RELEASE_IDENTITY_NAME"
CERT_BASE64="${LEXIRAY_RELEASE_CERT_P12_BASE64:-}"
CERT_PASSWORD="${LEXIRAY_RELEASE_CERT_PASSWORD:-}"
KEYCHAIN_PATH="${LEXIRAY_RELEASE_KEYCHAIN_PATH:-$ROOT_DIR/build/release-signing.keychain-db}"
KEYCHAIN_PASSWORD="${LEXIRAY_RELEASE_KEYCHAIN_PASSWORD:-$(/usr/bin/uuidgen)}"
P12_PATH="$ROOT_DIR/build/release-signing.p12"

if ! lexiray_require_github_fallback_context "${LEXIRAY_RELEASE_SOURCE_COMMIT:-}"; then
  echo "Ephemeral shell-based release identity import is restricted to GitHub Actions." >&2
  echo "For a local one-time import, use Keychain Access so no password enters the shell or agent session." >&2
  exit 1
fi

if [[ -z "$CERT_BASE64" ]]; then
  echo "LEXIRAY_RELEASE_CERT_P12_BASE64 must be set for release signing." >&2
  exit 1
fi

if [[ -z "$CERT_PASSWORD" ]]; then
  echo "LEXIRAY_RELEASE_CERT_PASSWORD must be set for release signing." >&2
  exit 1
fi

mkdir -p "$ROOT_DIR/build"

# Never inspect or unlock a previous keychain at this path. Remove only its
# search-list reference, then treat the file as an unrecoverable build artifact.
retained_keychains=()
while IFS= read -r keychain; do
  keychain="$(/usr/bin/sed -E 's/^[[:space:]]*"//; s/"[[:space:]]*$//' <<<"$keychain")"
  [[ -n "$keychain" && "$keychain" != "$KEYCHAIN_PATH" ]] && retained_keychains+=("$keychain")
done < <(/usr/bin/security list-keychains -d user 2>/dev/null || true)
/usr/bin/security list-keychains -d user -s "${retained_keychains[@]}"
rm -f "$KEYCHAIN_PATH" "$P12_PATH"
trap 'rm -f "$P12_PATH"' EXIT

if ! printf '%s' "$CERT_BASE64" | /usr/bin/base64 --decode >"$P12_PATH" 2>/dev/null; then
  printf '%s' "$CERT_BASE64" | /usr/bin/base64 -D >"$P12_PATH"
fi

/usr/bin/security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
/usr/bin/security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
/usr/bin/security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

/usr/bin/security list-keychains -d user -s "$KEYCHAIN_PATH" "${retained_keychains[@]}"

/usr/bin/security import "$P12_PATH" \
  -k "$KEYCHAIN_PATH" \
  -P "$CERT_PASSWORD" \
  -T /usr/bin/codesign \
  -T /usr/bin/security >/dev/null

/usr/bin/security set-key-partition-list \
  -S apple-tool:,apple:,codesign: \
  -s \
  -k "$KEYCHAIN_PASSWORD" \
  "$KEYCHAIN_PATH" >/dev/null

if ! /usr/bin/security find-identity -p codesigning "$KEYCHAIN_PATH" |
  /usr/bin/grep -E "[[:space:]]$LEXIRAY_RELEASE_CERT_SHA1[[:space:]]+\"$IDENTITY_NAME\"" >/dev/null ||
  ! lexiray_has_fixed_release_certificate "$KEYCHAIN_PATH"; then
  echo "Imported certificate, but did not find signing identity \"$IDENTITY_NAME\"." >&2
  /usr/bin/security find-identity -p codesigning "$KEYCHAIN_PATH" >&2
  /usr/bin/security find-identity -p codesigning -v "$KEYCHAIN_PATH" >&2
  exit 1
fi

echo "Imported release signing identity \"$IDENTITY_NAME\" into $KEYCHAIN_PATH."

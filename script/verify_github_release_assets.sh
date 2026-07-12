#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <version-without-v>" >&2
  exit 2
fi

VERSION="$1"
TAG="v$VERSION"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=release_identity.sh
source "$ROOT_DIR/script/release_identity.sh"
REPOSITORY="$LEXIRAY_RELEASE_REPOSITORY"
INFO_PLIST="$ROOT_DIR/LexiRay/Resources/Info.plist"
DMG_NAME="LexiRay-$VERSION.dmg"
SHA_NAME="$DMG_NAME.sha256"

if ! lexiray_validate_release_version "$VERSION"; then
  echo "Invalid version. Pass a version without v, for example: $0 0.4.1" >&2
  exit 2
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "gh is required to inspect GitHub Releases." >&2
  exit 127
fi

plist_version="$(
  /usr/bin/awk '
    /<key>CFBundleShortVersionString<\/key>/ {
      getline
      gsub(/^[[:space:]]*<string>|<\/string>[[:space:]]*$/, "", $0)
      print
      exit
    }
  ' "$INFO_PLIST"
)"
if [[ "$plist_version" != "$VERSION" ]]; then
  echo "Info.plist CFBundleShortVersionString is $plist_version, expected $VERSION." >&2
  exit 1
fi

if ! /usr/bin/grep -F "## [$VERSION]" "$ROOT_DIR/CHANGELOG.md" >/dev/null; then
  echo "CHANGELOG.md must contain a section for $VERSION." >&2
  exit 1
fi

assets="$(gh release view "$TAG" --repo "$REPOSITORY" --json assets --jq '.assets[].name' 2>/dev/null || true)"
if ! /usr/bin/grep -Fx "$DMG_NAME" <<<"$assets" >/dev/null ||
  ! /usr/bin/grep -Fx "$SHA_NAME" <<<"$assets" >/dev/null; then
  echo "GitHub Release $TAG is missing required assets:" >&2
  echo "  $DMG_NAME" >&2
  echo "  $SHA_NAME" >&2
  echo "Current assets:" >&2
  printf '%s\n' "$assets" >&2
  exit 1
fi

tmp_dir="$(/usr/bin/mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

gh release download "$TAG" \
  --repo "$REPOSITORY" \
  --pattern "$DMG_NAME" \
  --pattern "$SHA_NAME" \
  --dir "$tmp_dir" \
  --clobber >/dev/null

if ! lexiray_verify_sha256_file "$tmp_dir/$SHA_NAME" "$tmp_dir/$DMG_NAME" "$DMG_NAME"; then
  echo "Published SHA-256 file is malformed or does not match $DMG_NAME." >&2
  exit 1
fi

release_url="$(gh release view "$TAG" --repo "$REPOSITORY" --json url --jq '.url')"
echo "Verified GitHub Release assets for $TAG: $release_url"

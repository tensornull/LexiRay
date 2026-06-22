#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <version-without-v>" >&2
  exit 2
fi

VERSION="$1"
TAG="v$VERSION"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFO_PLIST="$ROOT_DIR/LexiRay/Resources/Info.plist"
DMG_NAME="LexiRay-$VERSION.dmg"
SHA_NAME="$DMG_NAME.sha256"

if [[ "$VERSION" == v* ]]; then
  echo "Pass the version without a leading v. Example: $0 0.2.0" >&2
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

assets=""
for attempt in {1..12}; do
  assets="$(gh release view "$TAG" --json assets --jq '.assets[].name' 2>/dev/null || true)"
  if /usr/bin/grep -Fx "$DMG_NAME" <<<"$assets" >/dev/null &&
    /usr/bin/grep -Fx "$SHA_NAME" <<<"$assets" >/dev/null; then
    break
  fi

  if [[ "$attempt" -eq 12 ]]; then
    echo "GitHub Release $TAG is missing required assets:" >&2
    echo "  $DMG_NAME" >&2
    echo "  $SHA_NAME" >&2
    echo "Current assets:" >&2
    printf '%s\n' "$assets" >&2
    exit 1
  fi

  sleep 10
done

tmp_dir="$(/usr/bin/mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

gh release download "$TAG" \
  --pattern "$DMG_NAME" \
  --pattern "$SHA_NAME" \
  --dir "$tmp_dir" \
  --clobber >/dev/null

if command -v shasum >/dev/null 2>&1; then
  (cd "$tmp_dir" && shasum -a 256 -c "$SHA_NAME")
else
  (cd "$tmp_dir" && sha256sum -c "$SHA_NAME")
fi

release_url="$(gh release view "$TAG" --json url --jq '.url')"
echo "Verified GitHub Release assets for $TAG: $release_url"

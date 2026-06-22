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
DMG_PATH="$ROOT_DIR/build/LexiRay-$VERSION.dmg"
SHA_PATH="$DMG_PATH.sha256"

if [[ "$VERSION" == v* ]]; then
  echo "Pass the version without a leading v. Example: $0 0.2.0" >&2
  exit 2
fi

cd "$ROOT_DIR"

if ! command -v gh >/dev/null 2>&1; then
  echo "gh is required to publish GitHub Releases." >&2
  exit 127
fi

if [[ -n "$(git status --porcelain --untracked-files=all)" ]]; then
  echo "Working tree must be clean before publishing a release." >&2
  git status --short
  exit 1
fi

remote_main="$(git ls-remote origin refs/heads/main | /usr/bin/awk '{print $1}')"
if [[ -z "$remote_main" ]]; then
  echo "Could not resolve origin/main." >&2
  exit 1
fi

remote_tag="$(
  git ls-remote --tags origin "refs/tags/$TAG" "refs/tags/$TAG^{}" |
    /usr/bin/awk '{
      last = $1
      if ($2 ~ /\^\{\}$/) {
        peeled = $1
      }
    }
    END {
      if (peeled != "") {
        print peeled
      } else if (last != "") {
        print last
      }
    }'
)"
if [[ -z "$remote_tag" ]]; then
  echo "Remote tag $TAG does not exist. Push the tag after main is green, then rerun." >&2
  exit 1
fi

if [[ "$remote_tag" != "$remote_main" ]]; then
  echo "Remote tag $TAG must point at origin/main before publishing." >&2
  echo "origin/main: $remote_main" >&2
  echo "$TAG: $remote_tag" >&2
  exit 1
fi

head_commit="$(git rev-parse HEAD)"
if [[ "$head_commit" != "$remote_tag" ]]; then
  echo "Local HEAD must match $TAG/origin/main before publishing." >&2
  echo "HEAD: $head_commit" >&2
  echo "$TAG: $remote_tag" >&2
  echo "Fetch and check out the release commit first." >&2
  exit 1
fi

plist_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
if [[ "$plist_version" != "$VERSION" ]]; then
  echo "Info.plist CFBundleShortVersionString is $plist_version, expected $VERSION." >&2
  exit 1
fi

if ! /usr/bin/grep -F "## [$VERSION]" CHANGELOG.md >/dev/null; then
  echo "CHANGELOG.md must contain a section for $VERSION." >&2
  exit 1
fi

./script/package_release_dmg.sh "$VERSION"
./script/verify_release_dmg.sh "$DMG_PATH" "$VERSION"

notes_path="$(/usr/bin/mktemp)"
trap 'rm -f "$notes_path"' EXIT
{
  printf 'LexiRay %s.\n\n' "$VERSION"
  /usr/bin/awk -v version="$VERSION" '
    /^## \[/ {
      if (index($0, "## [" version "]") == 1) {
        in_section = 1
        next
      }
      if (in_section) {
        exit
      }
    }
    in_section {
      print
    }
  ' CHANGELOG.md
  printf '\nRelease artifact note:\n\n'
  printf -- '- This DMG contains a fixed self-signed, non-notarized app. macOS Gatekeeper may still show a trust warning.\n'
  printf -- '- Verify the downloaded DMG with the published `.sha256` file before installing.\n'
} >"$notes_path"

if gh release view "$TAG" >/dev/null 2>&1; then
  gh release upload "$TAG" "$DMG_PATH" "$SHA_PATH" --clobber
  gh release edit "$TAG" \
    --title "LexiRay $VERSION" \
    --notes-file "$notes_path" \
    --draft=false \
    --prerelease=false
else
  gh release create "$TAG" \
    "$DMG_PATH" \
    "$SHA_PATH" \
    --title "LexiRay $VERSION" \
    --notes-file "$notes_path"
fi

./script/verify_github_release_assets.sh "$VERSION"

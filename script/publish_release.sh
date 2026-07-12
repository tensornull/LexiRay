#!/usr/bin/env bash
set -euo pipefail
export GH_PROMPT_DISABLED=1
export GIT_TERMINAL_PROMPT=0

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: $0 <version-without-v> [--skip-package]" >&2
  exit 2
fi

VERSION="$1"
SKIP_PACKAGE=0
if [[ $# -eq 2 ]]; then
  if [[ "$2" != --skip-package ]]; then
    echo "usage: $0 <version-without-v> [--skip-package]" >&2
    exit 2
  fi
  SKIP_PACKAGE=1
fi
TAG="v$VERSION"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=release_identity.sh
source "$ROOT_DIR/script/release_identity.sh"
# shellcheck source=release_capability.sh
source "$ROOT_DIR/script/release_capability.sh"
REPOSITORY="$LEXIRAY_RELEASE_REPOSITORY"
INFO_PLIST="$ROOT_DIR/LexiRay/Resources/Info.plist"
DMG_PATH="$ROOT_DIR/build/LexiRay-$VERSION.dmg"
SHA_PATH="$DMG_PATH.sha256"

if ! lexiray_validate_release_version "$VERSION"; then
  echo "Invalid version. Pass a version without v, for example: $0 0.4.1" >&2
  exit 2
fi

cd "$ROOT_DIR"

release_mode="${LEXIRAY_RELEASE_ORCHESTRATED:-}"
case "$release_mode" in
  local|fallback-confirm) ;;
  *)
    echo "Direct local publication is disabled. Use script/release.sh publish/status." >&2
    exit 1
    ;;
esac
[[ "${GITHUB_ACTIONS:-}" != true ]] || {
  echo "GitHub fallback builders may create artifacts, but cannot publish a public release." >&2
  exit 1
}
lexiray_require_release_capability "$ROOT_DIR" "$VERSION" "$release_mode" || {
  echo "Release publication requires a live, locked release.sh capability." >&2
  exit 1
}
"$ROOT_DIR/script/acceptance_receipt.sh" require-handoff >/dev/null

lexiray_validate_release_origin "$ROOT_DIR" origin || {
  echo "origin must point at github.com/$REPOSITORY." >&2
  exit 1
}

if ! command -v gh >/dev/null 2>&1; then
  echo "gh is required to publish GitHub Releases." >&2
  exit 127
fi

if [[ -n "$(git status --porcelain --untracked-files=all)" ]]; then
  echo "Working tree must be clean before publishing a release." >&2
  git status --short
  exit 1
fi

remote_main="$(gh api "repos/$REPOSITORY/commits/main" --jq '.sha' 2>/dev/null || true)"
if [[ -z "$remote_main" ]]; then
  echo "Could not resolve origin/main." >&2
  exit 1
fi

remote_tag="$(gh api "repos/$REPOSITORY/commits/$TAG" --jq '.sha' 2>/dev/null || true)"
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
plist_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
source_commit="$(git rev-parse HEAD)"
source_fingerprint="$("$ROOT_DIR/script/acceptance_receipt.sh" fingerprint)"
if [[ "$plist_version" != "$VERSION" ]]; then
  echo "Info.plist CFBundleShortVersionString is $plist_version, expected $VERSION." >&2
  exit 1
fi
if ! [[ "$plist_build" =~ ^[0-9]+$ ]] || [[ "$plist_build" -lt 1 ]]; then
  echo "Info.plist CFBundleVersion must be a positive integer, got: $plist_build" >&2
  exit 1
fi

if ! /usr/bin/grep -F "## [$VERSION]" CHANGELOG.md >/dev/null; then
  echo "CHANGELOG.md must contain a section for $VERSION." >&2
  exit 1
fi

if [[ "$SKIP_PACKAGE" -eq 0 ]]; then
  ./script/package_release_dmg.sh "$VERSION"
elif [[ ! -s "$DMG_PATH" || ! -s "$SHA_PATH" ]]; then
  echo "--skip-package requires existing DMG and SHA-256 artifacts." >&2
  exit 1
fi
unset LEXIRAY_RELEASE_CERT_P12_BASE64
unset LEXIRAY_RELEASE_CERT_PASSWORD
unset LEXIRAY_RELEASE_KEYCHAIN_PASSWORD
./script/verify_release_dmg.sh \
  "$DMG_PATH" "$VERSION" "$plist_build" "$source_commit" "$source_fingerprint"
if ! lexiray_verify_sha256_file "$SHA_PATH" "$DMG_PATH" "$(basename "$DMG_PATH")"; then
  echo "SHA-256 file is malformed or does not match the release DMG." >&2
  exit 1
fi

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

release_is_draft="$(
  gh release view "$TAG" --repo "$REPOSITORY" --json isDraft --jq '.isDraft' 2>/dev/null || true
)"
if [[ "$release_is_draft" == false ]]; then
  if ! ./script/verify_github_release_assets.sh "$VERSION"; then
    echo "Existing public release assets are invalid; refusing to clobber a public release." >&2
    echo "Repair or remove the public release explicitly, then resume through script/release.sh." >&2
    exit 1
  fi
  gh release edit "$TAG" \
    --repo "$REPOSITORY" \
    --title "LexiRay $VERSION" \
    --notes-file "$notes_path" \
    --draft=false \
    --prerelease=false
else
  if [[ "$release_is_draft" != true ]]; then
    gh release create "$TAG" \
      --repo "$REPOSITORY" \
      --draft \
      --title "LexiRay $VERSION" \
      --notes-file "$notes_path" \
      --verify-tag
  else
    gh release edit "$TAG" \
      --repo "$REPOSITORY" \
      --title "LexiRay $VERSION" \
      --notes-file "$notes_path" \
      --draft=true \
      --prerelease=false
  fi
  gh release upload "$TAG" "$DMG_PATH" "$SHA_PATH" --repo "$REPOSITORY" --clobber
  ./script/verify_github_release_assets.sh "$VERSION"
  gh release edit "$TAG" \
    --repo "$REPOSITORY" \
    --title "LexiRay $VERSION" \
    --notes-file "$notes_path" \
    --draft=false \
    --prerelease=false
fi

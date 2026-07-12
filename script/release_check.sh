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

cd "$ROOT_DIR"

if ! lexiray_validate_release_version "$VERSION"; then
  echo "Invalid version. Pass a version without v, for example: $0 0.4.1" >&2
  exit 2
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "release_check.sh must run inside a git worktree." >&2
  exit 1
fi

command -v gh >/dev/null 2>&1 || {
  echo "gh is required for noninteractive release checks." >&2
  exit 127
}
lexiray_validate_release_origin "$ROOT_DIR" origin || {
  echo "origin must point at github.com/$REPOSITORY." >&2
  exit 1
}

if [[ -n "$(git status --porcelain --untracked-files=all)" ]]; then
  echo "Working tree must be clean before a release check." >&2
  git status --short
  exit 1
fi

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "Local tag $TAG already exists." >&2
  exit 1
fi

set +e
remote_tag_output="$(gh api -i "repos/$REPOSITORY/git/ref/tags/$TAG" 2>&1)"
remote_tag_status=$?
set -e

if [[ "$remote_tag_status" -eq 0 ]]; then
  echo "Remote tag $TAG already exists." >&2
  exit 1
fi

if [[ "$remote_tag_status" -ne 0 ]] && ! /usr/bin/grep -E 'HTTP/[0-9.]+ 404' <<<"$remote_tag_output" >/dev/null; then
  echo "Could not verify whether remote tag $TAG exists." >&2
  printf '%s\n' "$remote_tag_output" >&2
  exit 1
fi

if ! grep -F "## [$VERSION]" CHANGELOG.md >/dev/null; then
  echo "CHANGELOG.md must contain a section for $VERSION." >&2
  exit 1
fi

plist_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
if [[ "$plist_version" != "$VERSION" ]]; then
  echo "Info.plist CFBundleShortVersionString is $plist_version, expected $VERSION." >&2
  exit 1
fi

build_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
if ! [[ "$build_version" =~ ^[0-9]+$ ]] || [[ "$build_version" -lt 1 ]]; then
  echo "Info.plist CFBundleVersion must be a positive integer." >&2
  exit 1
fi

"$ROOT_DIR/script/acceptance_receipt.sh" require-candidate >/dev/null
"$ROOT_DIR/script/verify.sh" pr

if [[ -n "$(git status --porcelain --untracked-files=all)" ]]; then
  echo "Working tree changed during release check." >&2
  git status --short
  exit 1
fi

echo "Release check passed for $TAG."

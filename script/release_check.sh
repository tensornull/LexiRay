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

cd "$ROOT_DIR"

if [[ "$VERSION" == v* ]]; then
  echo "Pass the version without a leading v. Example: $0 0.1.2" >&2
  exit 2
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "release_check.sh must run inside a git worktree." >&2
  exit 1
fi

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
git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1
remote_tag_status=$?
set -e

if [[ "$remote_tag_status" -eq 0 ]]; then
  echo "Remote tag $TAG already exists." >&2
  exit 1
fi

if [[ "$remote_tag_status" -ne 2 ]]; then
  echo "Could not verify whether remote tag $TAG exists." >&2
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

"$ROOT_DIR/script/ci_local.sh"

if [[ -n "$(git status --porcelain --untracked-files=all)" ]]; then
  echo "Working tree changed during release check." >&2
  git status --short
  exit 1
fi

echo "Release check passed for $TAG."

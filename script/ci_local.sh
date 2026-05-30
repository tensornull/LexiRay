#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/LexiRay.xcodeproj"

cd "$ROOT_DIR"

cleanup() {
  "$ROOT_DIR/script/clean_dev_apps.sh" --apply
}

trap cleanup EXIT

command -v xcodegen >/dev/null 2>&1 || {
  echo "xcodegen is required. Install with: brew install xcodegen" >&2
  exit 127
}

command -v swiftformat >/dev/null 2>&1 || {
  echo "swiftformat is required. Install with: brew install swiftformat" >&2
  exit 127
}

cleanup
xcodebuild -version
xcodegen generate
swiftformat LexiRay LexiRayTests Package.swift --lint
xcodebuild test \
  -project "$PROJECT" \
  -scheme LexiRay \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  SWIFT_COMPILATION_MODE=wholemodule

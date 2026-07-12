#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/LexiRay.xcodeproj"

cd "$ROOT_DIR"
SOURCE_FINGERPRINT_BEFORE="$("$ROOT_DIR/script/acceptance_receipt.sh" fingerprint)"

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

command -v rg >/dev/null 2>&1 || {
  echo "ripgrep is required. Install with: brew install ripgrep" >&2
  exit 127
}

cleanup
xcodebuild -version
"$ROOT_DIR/script/context_lint.sh"
xcodegen generate
swiftformat LexiRay LexiRayTests Package.swift --lint
fingerprint="$($ROOT_DIR/script/acceptance_receipt.sh fingerprint)"
result_bundle="$ROOT_DIR/build/acceptance/l3-$fingerprint.xcresult"
rm -rf "$result_bundle"
mkdir -p "$ROOT_DIR/build/acceptance"
xcodebuild test \
  -project "$PROJECT" \
  -scheme LexiRay \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM= \
  SWIFT_COMPILATION_MODE=wholemodule \
  -resultBundlePath "$result_bundle"

# Cleanup is part of the successful gate. Write reusable L3 evidence only after
# it succeeds, so an interrupted or partially cleaned run cannot be reused.
cleanup
trap - EXIT
SOURCE_FINGERPRINT_AFTER="$("$ROOT_DIR/script/acceptance_receipt.sh" fingerprint)"
if [[ "$SOURCE_FINGERPRINT_AFTER" != "$SOURCE_FINGERPRINT_BEFORE" ]]; then
  echo "Source inputs changed during ci_local.sh; refusing to write reusable L3 evidence." >&2
  exit 1
fi
"$ROOT_DIR/script/acceptance_receipt.sh" record-l3 "$result_bundle" >/dev/null
echo "L3_ACCEPTANCE_PASS"

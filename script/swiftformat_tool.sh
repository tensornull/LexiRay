#!/usr/bin/env bash
set -euo pipefail

LEXIRAY_SWIFTFORMAT_VERSION="0.62.1"
SWIFTFORMAT_TOOL="${LEXIRAY_SWIFTFORMAT_TOOL:-swiftformat}"

if [[ "$SWIFTFORMAT_TOOL" == */* ]]; then
  [[ -x "$SWIFTFORMAT_TOOL" ]] || {
    echo "Pinned SwiftFormat is unavailable or not executable: $SWIFTFORMAT_TOOL" >&2
    exit 127
  }
else
  SWIFTFORMAT_TOOL="$(command -v "$SWIFTFORMAT_TOOL" || true)"
  [[ -n "$SWIFTFORMAT_TOOL" ]] || {
    echo "SwiftFormat $LEXIRAY_SWIFTFORMAT_VERSION is required." >&2
    echo "Run: ./script/install_swiftformat.sh build/tools" >&2
    exit 127
  }
fi

actual_version="$($SWIFTFORMAT_TOOL --version)"
if [[ "$actual_version" != "$LEXIRAY_SWIFTFORMAT_VERSION" ]]; then
  echo "SwiftFormat version mismatch: expected $LEXIRAY_SWIFTFORMAT_VERSION, found $actual_version" >&2
  echo "Run: ./script/install_swiftformat.sh build/tools" >&2
  echo "Then set LEXIRAY_SWIFTFORMAT_TOOL=build/tools/swiftformat" >&2
  exit 1
fi

exec "$SWIFTFORMAT_TOOL" "$@"

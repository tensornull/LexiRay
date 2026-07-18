#!/usr/bin/env bash
set -euo pipefail

SWIFTFORMAT_VERSION="0.62.1"
SWIFTFORMAT_ARCHIVE_SHA256="7cb1cb1fae04932047c7015441c543848e8e60e1572d808d080e0a1f1661114a"
SWIFTFORMAT_ARCHIVE_URL="https://github.com/nicklockwood/SwiftFormat/releases/download/$SWIFTFORMAT_VERSION/swiftformat.zip"
DESTINATION_DIR="${1:-}"

if [[ -z "$DESTINATION_DIR" ]]; then
  echo "usage: $0 <destination-directory>" >&2
  exit 2
fi

mkdir -p "$DESTINATION_DIR"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lexiray-swiftformat.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

ARCHIVE_PATH="$TEMP_DIR/swiftformat.zip"
curl --fail --location --silent --show-error "$SWIFTFORMAT_ARCHIVE_URL" --output "$ARCHIVE_PATH"
printf '%s  %s\n' "$SWIFTFORMAT_ARCHIVE_SHA256" "$ARCHIVE_PATH" | shasum -a 256 --check
unzip -q "$ARCHIVE_PATH" -d "$TEMP_DIR/extracted"
install -m 0755 "$TEMP_DIR/extracted/swiftformat" "$DESTINATION_DIR/swiftformat"

actual_version="$($DESTINATION_DIR/swiftformat --version)"
if [[ "$actual_version" != "$SWIFTFORMAT_VERSION" ]]; then
  echo "Installed SwiftFormat version mismatch: expected $SWIFTFORMAT_VERSION, found $actual_version" >&2
  exit 1
fi

echo "SWIFTFORMAT_INSTALL_PASS[$SWIFTFORMAT_VERSION]: $DESTINATION_DIR/swiftformat"

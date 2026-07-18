#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lexiray-swiftformat-tool-test.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

MOCK_TOOL="$TEMP_DIR/swiftformat"
MOCK_LOG="$TEMP_DIR/invocations.log"
cat >"$MOCK_TOOL" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == --version ]]; then
  printf '%s\n' "${MOCK_SWIFTFORMAT_VERSION:?}"
  exit 0
fi
printf '%s\n' "$*" >>"${MOCK_SWIFTFORMAT_LOG:?}"
MOCK
chmod +x "$MOCK_TOOL"

MOCK_SWIFTFORMAT_VERSION=0.62.1 \
  MOCK_SWIFTFORMAT_LOG="$MOCK_LOG" \
  LEXIRAY_SWIFTFORMAT_TOOL="$MOCK_TOOL" \
  "$ROOT_DIR/script/swiftformat_tool.sh" LexiRay --lint
grep -Fx 'LexiRay --lint' "$MOCK_LOG" >/dev/null

if MOCK_SWIFTFORMAT_VERSION=0.61.1 \
  MOCK_SWIFTFORMAT_LOG="$MOCK_LOG" \
  LEXIRAY_SWIFTFORMAT_TOOL="$MOCK_TOOL" \
  "$ROOT_DIR/script/swiftformat_tool.sh" --version >"$TEMP_DIR/mismatch.out" 2>&1; then
  echo "version mismatch unexpectedly passed" >&2
  exit 1
fi
grep -F 'expected 0.62.1, found 0.61.1' "$TEMP_DIR/mismatch.out" >/dev/null

echo "SWIFTFORMAT_TOOL_TEST_PASS"

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lexiray-panel-border-test.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cd "$ROOT_DIR"
mkdir -p "$WORK_DIR/module-cache"
xcrun swiftc \
  -module-cache-path "$WORK_DIR/module-cache" \
  script/ui/panel_border_evidence.swift \
  script/tests/panel_border_evidence_test.swift \
  -o "$WORK_DIR/panel-border-evidence-test"
"$WORK_DIR/panel-border-evidence-test"

cat \
  script/ui/panel_border_evidence.swift \
  script/ui/lib.swift \
  script/ui/scenarios/panel_visual_states.swift |
  xcrun swiftc -module-cache-path "$WORK_DIR/module-cache" -typecheck -

echo "PANEL_BORDER_SCENARIO_TYPECHECK_PASS"

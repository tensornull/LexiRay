#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lexiray-computer-use-scope.XXXXXX")"
CHANGED="$WORK_DIR/changed.txt"
trap 'rm -rf "$WORK_DIR"' EXIT

assert_scope() {
  local expected="$1"
  shift
  printf '%s\n' "$@" >"$CHANGED"
  actual="$("$ROOT_DIR/script/computer_use_scope.sh" "$CHANGED")"
  [[ "$actual" == "$expected" ]] || {
    echo "Computer Use scope mismatch: expected=$expected actual=$actual" >&2
    exit 1
  }
}

assert_scope 'launch,login_item_settings' \
  LexiRay/Services/LoginItemService.swift \
  LexiRay/Views/SettingsView.swift
assert_scope 'launch,selection_hotkey' LexiRay/Services/TextSelectionService.swift
assert_scope 'launch,panel_visual_states' LexiRay/Views/FloatingPanelView.swift
assert_scope 'launch,ocr_result_display_1,ocr_result_display_2,ocr_multi_display' \
  LexiRay/Services/OCRService.swift
assert_scope 'launch,login_item_settings,speech_controls,ocr_result_display_1,ocr_result_display_2,ocr_multi_display' \
  LexiRay/Services/OCRService.swift \
  LexiRay/App/AppDelegate.swift \
  LexiRay/Services/SpeechService.swift
assert_scope 'launch' README.md .github/workflows/ci.yml script/ci_scope.sh

if "$ROOT_DIR/script/computer_use_scope.sh" "$WORK_DIR/missing" >/dev/null 2>&1; then
  echo "Computer Use scope accepted a missing change manifest" >&2
  exit 1
fi

echo "COMPUTER_USE_SCOPE_TEST_PASS"

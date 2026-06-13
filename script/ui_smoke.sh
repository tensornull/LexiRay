#!/usr/bin/env bash
# Back-compat entry point. The smoke suite now lives in script/ui/ as
# individually runnable scenarios with screenshot evidence.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -n "${LEXIRAY_UI_SMOKE_SCREENSHOT_DIR:-}" ]]; then
  export LEXIRAY_UI_ARTIFACT_DIR="$LEXIRAY_UI_SMOKE_SCREENSHOT_DIR"
fi

exec "$ROOT_DIR/script/ui/run.sh" "$@"

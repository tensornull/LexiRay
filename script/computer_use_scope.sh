#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: script/computer_use_scope.sh <changed-files>" >&2
  exit 2
}

[[ $# -eq 1 ]] || usage
changed_files="$1"
[[ -f "$changed_files" ]] || {
  echo "Computer Use scope input is missing: $changed_files" >&2
  exit 1
}

matches() {
  grep -E "$1" "$changed_files" >/dev/null 2>&1
}

# Keep this order aligned with the receipt's scenario catalog. The result is
# frozen into the candidate receipt, so later handoff commands cannot narrow it.
scenarios=(launch)

if matches '(^|/)(LoginItem[^/]*|SettingsView|AppRuntime|AppDelegate)\.swift$'; then
  scenarios+=(login_item_settings)
fi
if matches '(^|/)(TextSelection[^/]*|GlobalHotKey[^/]*|Selection[^/]*)\.swift$'; then
  scenarios+=(selection_hotkey)
fi
if matches '(^|/)(SourceTextEditor|MainView)\.swift$'; then
  scenarios+=(source_editor)
fi
if matches '(^|/)(Language[^/]*)\.swift$'; then
  scenarios+=(language_direction)
fi
if matches '(^|/)(Speech[^/]*)\.swift$'; then
  scenarios+=(speech_controls)
fi
if matches '(^|/)(FloatingPanel[^/]*|WindowReporting)\.swift$'; then
  scenarios+=(panel_visual_states)
fi
if matches '(^|/)(OCR[^/]*)\.swift$'; then
  scenarios+=(ocr_result_display_1 ocr_result_display_2 ocr_multi_display)
fi

printf '%s\n' "${scenarios[@]}" | paste -sd, -

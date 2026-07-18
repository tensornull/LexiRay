#!/usr/bin/env bash
set -euo pipefail

[[ $# -eq 1 ]] || { echo "usage: $0 <changed-files>" >&2; exit 2; }
CHANGED_FILES="$1"
[[ -f "$CHANGED_FILES" ]] || { echo "changed-files input is missing: $CHANGED_FILES" >&2; exit 2; }

needs_xcode=false
needs_script_tests=false
needs_prototype=false
found_path=false

while IFS= read -r path; do
  [[ -n "$path" ]] || continue
  found_path=true
  case "$path" in
    LexiRay/*|LexiRayTests/*|Package.swift|project.yml|.swiftformat)
      needs_xcode=true
      ;;
    script/*|.github/*)
      needs_script_tests=true
      ;;
    prototypes/*)
      needs_prototype=true
      ;;
  esac
done <"$CHANGED_FILES"

# A missing/empty diff is ambiguous (for example, a new branch push). Choose
# the safe full lane rather than silently skipping compilation.
if [[ "$found_path" == false ]]; then
  needs_xcode=true
  needs_script_tests=true
fi

echo "needs_xcode=$needs_xcode"
echo "needs_script_tests=$needs_script_tests"
echo "needs_prototype=$needs_prototype"

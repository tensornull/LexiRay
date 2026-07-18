#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAX_JOBS="${LEXIRAY_CONTROL_PLANE_JOBS:-4}"

if ! [[ "$MAX_JOBS" =~ ^[1-8]$ ]]; then
  echo "LEXIRAY_CONTROL_PLANE_JOBS must be an integer from 1 through 8." >&2
  exit 2
fi

cd "$ROOT_DIR"
tests=()
for test_script in script/tests/*_test.sh; do
  [[ -x "$test_script" ]] || continue
  tests+=("$test_script")
done

if [[ "${#tests[@]}" -eq 0 ]]; then
  echo "--- Script tests: none registered"
  exit 0
fi

printf '%s\0' "${tests[@]}" | xargs -0 -n 1 -P "$MAX_JOBS" /bin/bash -c '
  test_script="$1"
  printf -- "--- Script test: %s\n" "$test_script"
  "$test_script"
' _

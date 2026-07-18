#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/lexiray-ci-scope.XXXXXX")"
CI_WORKFLOW="$ROOT_DIR/.github/workflows/ci.yml"
CONTROL_PLANE_RUNNER="$ROOT_DIR/script/run_control_plane_tests.sh"
trap 'rm -rf "$TMP_ROOT"' EXIT

assert_scope() {
  local name="$1"
  local expected="$2"
  shift 2
  printf '%s\n' "$@" >"$TMP_ROOT/$name.txt"
  actual="$("$ROOT_DIR/script/ci_scope.sh" "$TMP_ROOT/$name.txt")"
  [[ "$actual" == "$expected" ]] || {
    echo "$name scope mismatch" >&2
    echo "expected:" >&2
    echo "$expected" >&2
    echo "actual:" >&2
    echo "$actual" >&2
    exit 1
  }
}

assert_scope swift $'needs_xcode=true\nneeds_script_tests=false\nneeds_prototype=false' \
  LexiRay/Services/LoginItemService.swift
assert_scope scripts $'needs_xcode=false\nneeds_script_tests=true\nneeds_prototype=false' \
  script/preflight.sh .github/workflows/ci.yml
assert_scope docs $'needs_xcode=false\nneeds_script_tests=false\nneeds_prototype=false' \
  README.md .agents/runbooks/ci.md
assert_scope prototype $'needs_xcode=false\nneeds_script_tests=false\nneeds_prototype=true' \
  prototypes/lexiray-current/src/App.jsx
assert_scope mixed $'needs_xcode=true\nneeds_script_tests=true\nneeds_prototype=false' \
  LexiRay/App/AppDelegate.swift script/login_item_system_probe.sh README.md
: >"$TMP_ROOT/empty.txt"
[[ "$("$ROOT_DIR/script/ci_scope.sh" "$TMP_ROOT/empty.txt")" == \
  $'needs_xcode=true\nneeds_script_tests=true\nneeds_prototype=false' ]]

rg -F "run: ./script/run_control_plane_tests.sh" "$CI_WORKFLOW" >/dev/null || {
  echo "CI script control-plane tests do not use the canonical runner" >&2
  exit 1
}
rg -F 'MAX_JOBS="${LEXIRAY_CONTROL_PLANE_JOBS:-4}"' "$CONTROL_PLANE_RUNNER" >/dev/null || {
  echo "control-plane runner does not default to four workers" >&2
  exit 1
}
rg -F 'xargs -0 -n 1 -P "$MAX_JOBS" /bin/bash -c' "$CONTROL_PLANE_RUNNER" >/dev/null || {
  echo "control-plane runner is not using bounded parallel execution" >&2
  exit 1
}
if rg -F 'for test_script in script/tests/*_test.sh' "$CI_WORKFLOW" >/dev/null; then
  echo "CI script control-plane tests regressed to serial execution" >&2
  exit 1
fi

echo "CI_SCOPE_PASS"

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/lexiray-ci-scope.XXXXXX")"
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

echo "CI_SCOPE_PASS"

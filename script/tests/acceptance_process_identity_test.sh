#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lexiray-process-identity.XXXXXX")"
FIXTURE="$WORK_DIR/AcceptanceProcessFixture"
ACTIVE_PID=""
trap '[[ -z "$ACTIVE_PID" ]] || kill "$ACTIVE_PID" >/dev/null 2>&1 || true; rm -rf "$WORK_DIR"' EXIT

printf '%s\n' \
  '#include <signal.h>' \
  '#include <unistd.h>' \
  'int main(void) { signal(SIGTERM, SIG_DFL); for (;;) pause(); }' \
  >"$WORK_DIR/fixture.c"
xcrun clang "$WORK_DIR/fixture.c" -o "$FIXTURE"

expected_arguments=(
  --lexiray-acceptance-profile
  --lexiray-acceptance-workspace-root "$ROOT_DIR"
  --lexiray-acceptance-root "$ROOT_DIR/build/acceptance-data/process-test"
  --lexiray-acceptance-defaults-suite io.github.tensornull.lexiray.acceptance.process-test
)

"$FIXTURE" "${expected_arguments[@]}" &
ACTIVE_PID=$!
process_start_time="$(/usr/bin/swift "$ROOT_DIR/script/acceptance_evidence.swift" process-identity \
  "$ACTIVE_PID" "$FIXTURE" -- "${expected_arguments[@]}")"
[[ "$process_start_time" =~ ^[1-9][0-9]*$ ]]
/usr/bin/swift "$ROOT_DIR/script/acceptance_evidence.swift" process \
  "$ACTIVE_PID" "$FIXTURE" "$process_start_time" -- "${expected_arguments[@]}"
if /usr/bin/swift "$ROOT_DIR/script/acceptance_evidence.swift" process \
  "$ACTIVE_PID" "$FIXTURE" "$((process_start_time + 1))" -- \
  "${expected_arguments[@]}" >/dev/null 2>&1; then
  echo "Acceptance process validator accepted the wrong kernel start time" >&2
  exit 1
fi
kill "$ACTIVE_PID"
wait "$ACTIVE_PID" >/dev/null 2>&1 || true
ACTIVE_PID=""

for spoofed_prefix in \
  "--lexiray-acceptance-root=$ROOT_DIR/build/acceptance-data/spoofed-root" \
  "--lexiray-acceptance-selection-pid=99999"; do
  "$FIXTURE" "$spoofed_prefix" "${expected_arguments[@]}" &
  ACTIVE_PID=$!
  if /usr/bin/swift "$ROOT_DIR/script/acceptance_evidence.swift" process \
    "$ACTIVE_PID" "$FIXTURE" -- "${expected_arguments[@]}" >/dev/null 2>&1; then
    echo "Acceptance process validator accepted a prefixed profile override: $spoofed_prefix" >&2
    exit 1
  fi
  kill "$ACTIVE_PID"
  wait "$ACTIVE_PID" >/dev/null 2>&1 || true
  ACTIVE_PID=""
done

spoofed_arguments=(
  --note=--lexiray-acceptance-profile
  --note=--lexiray-acceptance-workspace-root "$ROOT_DIR"
  --note=--lexiray-acceptance-root "$ROOT_DIR/build/acceptance-data/process-test"
  --note=--lexiray-acceptance-defaults-suite io.github.tensornull.lexiray.acceptance.process-test
)
"$FIXTURE" "${spoofed_arguments[@]}" &
ACTIVE_PID=$!
if /usr/bin/swift "$ROOT_DIR/script/acceptance_evidence.swift" process \
  "$ACTIVE_PID" "$FIXTURE" -- "${expected_arguments[@]}" >/dev/null 2>&1; then
  echo "Acceptance process validator accepted flag substrings inside unrelated argv tokens" >&2
  exit 1
fi
kill "$ACTIVE_PID"
wait "$ACTIVE_PID" >/dev/null 2>&1 || true
ACTIVE_PID=""

echo "ACCEPTANCE_PROCESS_IDENTITY_TEST_PASS"

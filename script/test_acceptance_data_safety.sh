#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="${1:-$ROOT_DIR/build/DerivedData/Build/Products/Debug/LexiRay.app}"
EXECUTABLE="$APP_BUNDLE/Contents/MacOS/LexiRay"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lexiray-data-safety.XXXXXX")"
ACCEPTANCE_WORKSPACE="$WORK_DIR/workspace"
SYNTHETIC_HOME="$WORK_DIR/home"
PRODUCTION_DATA="$SYNTHETIC_HOME/.lexiray"
PRODUCTION_DEFAULTS="io.github.tensornull.lexiray"
PROVIDER_SENTINEL="$WORK_DIR/provider-sentinel"
HISTORY_SENTINEL="$WORK_DIR/history-sentinel"
DEFAULTS_BEFORE="$WORK_DIR/defaults-before.plist"
ACTIVE_PID=""

cleanup() {
  if [[ -n "$ACTIVE_PID" ]] && kill -0 "$ACTIVE_PID" >/dev/null 2>&1; then
    kill -9 "$ACTIVE_PID" >/dev/null 2>&1 || true
    wait "$ACTIVE_PID" >/dev/null 2>&1 || true
  fi
  if [[ "${LEXIRAY_KEEP_DATA_SAFETY_WORK_DIR:-0}" == 1 ]]; then
    echo "DATA_SAFETY_DIAGNOSTICS=$WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

[[ -x "$EXECUTABLE" ]] || {
  echo "Data-safety test requires a built app: $APP_BUNDLE" >&2
  exit 2
}

mkdir -p "$PRODUCTION_DATA"
printf '%s\n' 'synthetic-real-provider-data' >"$PRODUCTION_DATA/providers.json"
printf '%s\n' 'synthetic-real-history-data' >"$PRODUCTION_DATA/history.json"
cp "$PRODUCTION_DATA/providers.json" "$PROVIDER_SENTINEL"
cp "$PRODUCTION_DATA/history.json" "$HISTORY_SENTINEL"

env HOME="$SYNTHETIC_HOME" CFFIXED_USER_HOME="$SYNTHETIC_HOME" \
  defaults write "$PRODUCTION_DEFAULTS" DataSafetySentinel -string 'synthetic-real-defaults'
env HOME="$SYNTHETIC_HOME" CFFIXED_USER_HOME="$SYNTHETIC_HOME" \
  defaults export "$PRODUCTION_DEFAULTS" "$DEFAULTS_BEFORE" >/dev/null

assert_production_unchanged() {
  local mode="$1"
  local defaults_after="$WORK_DIR/defaults-after-$mode.plist"
  cmp -s "$PROVIDER_SENTINEL" "$PRODUCTION_DATA/providers.json" || {
    echo "DATA_SAFETY_FAIL[$mode]: production-shaped providers changed" >&2
    [[ -f "$PRODUCTION_DATA/providers.json" ]] &&
      /usr/bin/shasum -a 256 "$PROVIDER_SENTINEL" "$PRODUCTION_DATA/providers.json" >&2
    return 1
  }
  cmp -s "$HISTORY_SENTINEL" "$PRODUCTION_DATA/history.json" || {
    echo "DATA_SAFETY_FAIL[$mode]: production-shaped history changed" >&2
    [[ -f "$PRODUCTION_DATA/history.json" ]] &&
      /usr/bin/shasum -a 256 "$HISTORY_SENTINEL" "$PRODUCTION_DATA/history.json" >&2
    return 1
  }
  env HOME="$SYNTHETIC_HOME" CFFIXED_USER_HOME="$SYNTHETIC_HOME" \
    defaults export "$PRODUCTION_DEFAULTS" "$defaults_after" >/dev/null
  cmp -s "$DEFAULTS_BEFORE" "$defaults_after" || {
    echo "DATA_SAFETY_FAIL[$mode]: production-shaped defaults changed" >&2
    return 1
  }
}

wait_until_running() {
  local pid="$1"
  local attempt
  for attempt in {1..40}; do
    kill -0 "$pid" >/dev/null 2>&1 && return 0
    sleep 0.05
  done
  return 1
}

wait_until_stopped() {
  local pid="$1"
  local attempt state
  for attempt in {1..80}; do
    state="$(ps -p "$pid" -o state= 2>/dev/null | tr -d '[:space:]')"
    if [[ -z "$state" || "$state" == Z* ]]; then
      wait "$pid" >/dev/null 2>&1 || true
      return 0
    fi
    sleep 0.05
  done
  return 1
}

request_app_termination() {
  swift - "$1" <<'SWIFT'
import AppKit

let pid = pid_t(CommandLine.arguments[1])!
for _ in 0 ..< 100 {
  if let app = NSRunningApplication(processIdentifier: pid), app.terminate() {
    exit(0)
  }
  Thread.sleep(forTimeInterval: 0.05)
}
exit(1)
SWIFT
}

launch_valid_profile() {
  local mode="$1"
  local root="$ACCEPTANCE_WORKSPACE/build/acceptance-data/$mode"
  local suite="io.github.tensornull.lexiray.acceptance.data-safety.$mode.$$"
  mkdir -p "$root"
  printf '%s\n' 'LexiRay acceptance root v1' >"$root/.lexiray-acceptance-root"
  cp "$ROOT_DIR/script/ui/fixtures/providers.json" "$root/providers.json"
  cp "$ROOT_DIR/script/ui/fixtures/history.json" "$root/history.json"
  (
    trap - EXIT HUP INT TERM
    exec env HOME="$SYNTHETIC_HOME" CFFIXED_USER_HOME="$SYNTHETIC_HOME" \
      "$EXECUTABLE" \
      --lexiray-acceptance-profile \
      --lexiray-acceptance-workspace-root "$ACCEPTANCE_WORKSPACE" \
      --lexiray-acceptance-root "$root" \
      --lexiray-acceptance-defaults-suite "$suite"
  ) >"$WORK_DIR/$mode.log" 2>&1 &
  ACTIVE_PID=$!
  wait_until_running "$ACTIVE_PID" || {
    echo "DATA_SAFETY_FAIL[$mode]: acceptance app did not start" >&2
    return 1
  }
}

# Normal app termination: ask AppKit to terminate the exact child process.
launch_valid_profile normal
request_app_termination "$ACTIVE_PID"
wait_until_stopped "$ACTIVE_PID" || {
  echo "DATA_SAFETY_FAIL[normal]: app did not terminate" >&2
  exit 1
}
ACTIVE_PID=""
assert_production_unchanged normal

# Invalid acceptance configuration must fail closed without touching the
# production-shaped sentinels.
unsafe_root="$PRODUCTION_DATA/acceptance"
(
  trap - EXIT HUP INT TERM
  exec env HOME="$SYNTHETIC_HOME" CFFIXED_USER_HOME="$SYNTHETIC_HOME" \
    "$EXECUTABLE" \
    --lexiray-acceptance-profile \
    --lexiray-acceptance-workspace-root "$ACCEPTANCE_WORKSPACE" \
    --lexiray-acceptance-root "$unsafe_root" \
    --lexiray-acceptance-defaults-suite "io.github.tensornull.lexiray.acceptance.data-safety.failure.$$"
) >"$WORK_DIR/failure.log" 2>&1 &
ACTIVE_PID=$!
if wait_until_stopped "$ACTIVE_PID"; then
  ACTIVE_PID=""
else
  echo "DATA_SAFETY_FAIL[failure]: unsafe profile did not fail closed" >&2
  exit 1
fi
assert_production_unchanged failure

# SIGINT proves ordinary interruption does not require reading or restoring the
# production-shaped state.
launch_valid_profile sigint
kill -INT "$ACTIVE_PID"
sleep 0.5
assert_production_unchanged sigint-delivered
if kill -0 "$ACTIVE_PID" >/dev/null 2>&1; then
  request_app_termination "$ACTIVE_PID"
fi
wait_until_stopped "$ACTIVE_PID" || {
  echo "DATA_SAFETY_FAIL[sigint]: exact test child could not be stopped after verification" >&2
  exit 1
}
ACTIVE_PID=""
assert_production_unchanged sigint

# SIGKILL proves isolation does not depend on a cleanup/restore handler.
launch_valid_profile sigkill
kill -9 "$ACTIVE_PID"
wait "$ACTIVE_PID" >/dev/null 2>&1 || true
ACTIVE_PID=""
assert_production_unchanged sigkill

echo "DATA_SAFETY_PASS: normal, fail-closed, SIGINT, and SIGKILL paths preserved synthetic production data"

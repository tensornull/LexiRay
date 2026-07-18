#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RECEIPT_TOOL="$ROOT_DIR/script/acceptance_receipt.sh"
APP_DST="/Applications/LexiRay.app"

die() {
  echo "LOGIN_ITEM_PROBE_ERROR: $*" >&2
  exit 1
}

prepare_probe_root() {
  local root="$1"
  [[ "$root" == "$ROOT_DIR"/build/acceptance-data/* && -d "$root" && ! -L "$root" ]] ||
    die "probe root must be a real directory below $ROOT_DIR/build/acceptance-data"
  [[ -f "$root/.lexiray-acceptance-root" && ! -L "$root/.lexiray-acceptance-root" ]] ||
    die "probe root is missing its acceptance marker"
  [[ "$(<"$root/.lexiray-acceptance-root")" == "LexiRay acceptance root v1" ]] ||
    die "probe root marker is invalid"
  [[ -f "$root/providers.json" && -f "$root/history.json" ]] ||
    die "probe root is missing isolated fixtures"
  [[ -d "$root/preferences-home" && ! -L "$root/preferences-home" ]] ||
    die "probe root is missing its isolated preferences home"
}

record_manifest() {
  local app="$1"
  local raw_result="$2"
  local process_status="$3"
  local fingerprint manifest_id manifest tmp_plist tmp_json identity_json status
  fingerprint="$($RECEIPT_TOOL field source_fingerprint)"
  manifest_id="$(/usr/bin/uuidgen | /usr/bin/tr '[:upper:]' '[:lower:]')"
  manifest="$ROOT_DIR/build/acceptance/login-item-probe-$fingerprint-$manifest_id.json"
  tmp_plist="$(mktemp "$ROOT_DIR/build/acceptance/.login-item-probe.XXXXXX")"
  tmp_json="$(mktemp "$ROOT_DIR/build/acceptance/.login-item-probe-json.XXXXXX")"
  identity_json="$(mktemp "$ROOT_DIR/build/acceptance/.login-item-identity.XXXXXX")"
  "$RECEIPT_TOOL" app-identity "$app" >"$identity_json"
  /usr/bin/plutil -convert xml1 -o "$tmp_plist" -- "$raw_result" || die "probe result is malformed"
  /usr/bin/plutil -insert source_fingerprint -string "$fingerprint" -- "$tmp_plist"
  /usr/bin/plutil -insert app_cdhash -string "$(/usr/bin/plutil -extract cdhash raw -n -- "$identity_json")" -- "$tmp_plist"
  /usr/bin/plutil -insert app_executable_sha256 -string "$(/usr/bin/plutil -extract executable_sha256 raw -n -- "$identity_json")" -- "$tmp_plist"
  /usr/bin/plutil -insert app_certificate_sha256 -string "$(/usr/bin/plutil -extract certificate_sha256 raw -n -- "$identity_json")" -- "$tmp_plist"
  /usr/bin/plutil -insert app_designated_requirement_sha256 -string "$(/usr/bin/plutil -extract designated_requirement_sha256 raw -n -- "$identity_json")" -- "$tmp_plist"
  /usr/bin/plutil -insert process_exit_status -integer "$process_status" -- "$tmp_plist"
  /usr/bin/plutil -convert json -r -o "$tmp_json" -- "$tmp_plist"
  /bin/mv -f "$tmp_json" "$manifest"
  /bin/rm -f "$tmp_plist" "$identity_json"
  /bin/chmod 600 "$manifest"
  status="$(/usr/bin/plutil -extract outcome raw -n -- "$manifest")"
  case "$status:$process_status" in
    passed:0|blocked:75|failed:1) ;;
    *) die "probe outcome '$status' does not match process exit $process_status" ;;
  esac
  "$RECEIPT_TOOL" mark-login-item-probe "$status" "$manifest" >/dev/null
  echo "LOGIN_ITEM_PROBE_MANIFEST=$manifest"
  echo "LOGIN_ITEM_PROBE_STATUS=$status"
  case "$status" in
    passed) return 0 ;;
    blocked) return 75 ;;
    failed) return 1 ;;
    *) die "probe returned unknown outcome: $status" ;;
  esac
}

run_probe() {
  local app="$1"
  local root="$2"
  local defaults_suite="$3"
  local executable output pid deadline process_status
  [[ "$app" == "$APP_DST" && -d "$app" && ! -L "$app" ]] ||
    die "probe must use the canonical installed app: $APP_DST"
  prepare_probe_root "$root"
  [[ "$defaults_suite" == io.github.tensornull.lexiray.acceptance.* ]] ||
    die "probe defaults suite is not isolated"
  "$RECEIPT_TOOL" verify-app-match "$app" >/dev/null ||
    die "installed app does not match the accepted candidate"
  output="$root/login-item-system-probe.json"
  [[ ! -e "$output" && ! -L "$output" ]] || die "probe output already exists: $output"
  executable="$app/Contents/MacOS/LexiRay"

  /usr/bin/env \
    HOME="$root/preferences-home" \
    CFFIXED_USER_HOME="$root/preferences-home" \
    CFPREFERENCES_AVOID_DAEMON=1 \
    "$executable" \
    --lexiray-acceptance-profile \
    --lexiray-acceptance-workspace-root "$ROOT_DIR" \
    --lexiray-acceptance-root "$root" \
    --lexiray-acceptance-defaults-suite "$defaults_suite" \
    --lexiray-login-item-system-probe &
  pid=$!
  deadline=$((SECONDS + 20))
  while kill -0 "$pid" >/dev/null 2>&1; do
    if ((SECONDS >= deadline)); then
      kill -TERM "$pid" >/dev/null 2>&1 || true
      wait "$pid" >/dev/null 2>&1 || true
      die "probe exceeded 20 seconds; Login Item state may require manual inspection"
    fi
    sleep 0.2
  done
  set +e
  wait "$pid"
  process_status=$?
  set -e
  [[ -f "$output" && ! -L "$output" && -s "$output" ]] ||
    die "probe process exited $process_status without evidence"
  record_manifest "$app" "$output" "$process_status"
}

run_standalone() {
  local fingerprint installed live_pids probe_id root suite
  "$RECEIPT_TOOL" require-candidate >/dev/null || die "current source has no accepted candidate"
  fingerprint="$($RECEIPT_TOOL field source_fingerprint)"
  installed="$($RECEIPT_TOOL field verification.installed_path)"
  [[ "$installed" == "$APP_DST" ]] || die "current candidate is not installed"
  live_pids="$(pgrep -x LexiRay 2>/dev/null || true)"
  [[ -z "$live_pids" ]] || die "quit the current LexiRay acceptance process before a standalone probe"
  probe_id="$(/usr/bin/uuidgen | /usr/bin/tr -d '-' | /usr/bin/tr '[:upper:]' '[:lower:]')"
  root="$ROOT_DIR/build/acceptance-data/login-item-probe-$fingerprint-$probe_id"
  /bin/mkdir -m 700 "$root"
  /bin/mkdir -m 700 "$root/preferences-home"
  printf '%s\n' 'LexiRay acceptance root v1' >"$root/.lexiray-acceptance-root"
  /bin/cp "$ROOT_DIR/script/ui/fixtures/computer-use-providers.json" "$root/providers.json"
  /bin/cp "$ROOT_DIR/script/ui/fixtures/history.json" "$root/history.json"
  /bin/chmod 600 "$root/.lexiray-acceptance-root" "$root/providers.json" "$root/history.json"
  suite="io.github.tensornull.lexiray.acceptance.login-item-probe.$probe_id"
  run_probe "$installed" "$root" "$suite"
}

case "${1:-}" in
  "") run_standalone ;;
  --install)
    [[ $# -eq 4 ]] || die "usage: $0 --install <app> <acceptance-root> <defaults-suite>"
    run_probe "$2" "$3" "$4"
    ;;
  *) die "usage: $0" ;;
esac

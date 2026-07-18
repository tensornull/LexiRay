#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lexiray-release-flow-test.XXXXXX")"
WORK_DIR="$(cd "$WORK_DIR" && pwd -P)"
BIN_DIR="$WORK_DIR/bin"
STATE_DIR="$WORK_DIR/state"
VERSION="9.9.9"
TAG="v$VERSION"
COMMIT="0123456789abcdef0123456789abcdef01234567"
STATE_KEY="$TAG-${COMMIT:0:12}"
STATE_FILE="$STATE_DIR/$TAG-$COMMIT.state"
LOCK_FILE="$WORK_DIR/release-lock/lock"
DISPATCH_ID="00000000-0000-4000-8000-000000000999"
trap 'rm -rf "$WORK_DIR"' EXIT

mkdir -p "$BIN_DIR" "$STATE_DIR" "$(dirname "$LOCK_FILE")"
chmod 700 "$(dirname "$LOCK_FILE")"
printf 'LexiRay release status mock v1\n' >"$WORK_DIR/.lexiray-release-test-harness"

cat >"$BIN_DIR/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == -C ]]; then
  shift 2
fi
if [[ "${1:-}" == remote && "${2:-}" == get-url && "${3:-}" == origin ]]; then
  printf 'git@github.com:tensornull/LexiRay.git\n'
  exit 0
fi
echo "unexpected git invocation: $*" >&2
exit 90
EOF

cat >"$BIN_DIR/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == api && "${2:-}" == "repos/tensornull/LexiRay/commits/$MOCK_TAG" ]]; then
  printf '%s\n' "$MOCK_COMMIT"
  exit 0
fi
if [[ "${1:-}" == release && "${2:-}" == list && "${MOCK_MODE:-}" == assets ]]; then
  printf 'ready\n'
  exit 0
fi
if [[ "${1:-}" == release && "${2:-}" == view ]]; then
  if [[ "${MOCK_MODE:-}" == assets ]]; then
    if [[ "$*" == *assets* ]]; then
      printf 'LexiRay-%s.dmg\nLexiRay-%s.dmg.sha256\n' "$MOCK_VERSION" "$MOCK_VERSION"
    else
      echo "unexpected release view: $*" >&2
      exit 91
    fi
    exit 0
  fi
  exit 1
fi

if [[ "${1:-}" == run && "${2:-}" == view && "${3:-}" == 999 ]]; then
  if [[ "$*" == *--log-failed* ]]; then
    echo "MOCK_FAILED_STEP"
    exit 0
  fi
  case "${MOCK_MODE:-}" in
    pending)
      printf 'in_progress||https://example.invalid/run/999|%s\n' "$MOCK_COMMIT"
      ;;
    failure)
      printf 'completed|failure|https://example.invalid/run/999|%s\n' "$MOCK_COMMIT"
      ;;
    *)
      echo "unexpected run-view mode: ${MOCK_MODE:-unset}" >&2
      exit 92
      ;;
  esac
  exit 0
fi

if [[ "${1:-}" == run && "${2:-}" == list ]]; then
  if [[ "${MOCK_MODE:-}" == query_error ]]; then
    exit 1
  fi
  if [[ "${MOCK_MODE:-}" == dispatch_query ]]; then
    [[ "$*" == *"$MOCK_DISPATCH_ID"* ]] || {
      echo "fallback run query omitted the unique dispatch ID" >&2
      exit 94
    }
    exit 0
  fi
  exit 0
fi

echo "unexpected gh invocation: $*" >&2
exit 93
EOF
chmod +x "$BIN_DIR/git" "$BIN_DIR/gh"

export MOCK_COMMIT="$COMMIT"
export MOCK_TAG="$TAG"
export MOCK_VERSION="$VERSION"
export MOCK_DISPATCH_ID="$DISPATCH_ID"

write_state() {
  local dispatch="${1:-}"
  local run_id="${2:-}"
  local correlation_key="${3:-$STATE_KEY}"
  local release_mode="${4:-fallback}"

  cat >"$STATE_FILE" <<EOF
schema_version=1
version=$VERSION
build=1
certificate_sha256=5A54594CFDFB1827E3A097EA43BF4674A6FCBFA2563D60DE178566AE860229F5
candidate_certificate_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
candidate_designated_requirement_sha256=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
candidate_entitlements_sha256=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
tag=$TAG
source_commit=$COMMIT
tag_commit=$COMMIT
source_fingerprint=0000000000000000000000000000000000000000000000000000000000000000
state_key=$correlation_key
doctor=complete
mode=$release_mode
EOF
  [[ -n "$dispatch" ]] && printf 'fallback_dispatch=%s\n' "$dispatch" >>"$STATE_FILE"
  [[ -n "$dispatch" ]] && printf 'fallback_dispatch_id=%s\n' "$DISPATCH_ID" >>"$STATE_FILE"
  [[ -n "$run_id" ]] && printf 'workflow_run_id=%s\n' "$run_id" >>"$STATE_FILE"
  return 0
}

run_status() {
  local mode="$1"
  local dry_run="${2:-}"

  set +e
  STATUS_OUTPUT="$(
    MOCK_MODE="$mode" \
      PATH="$BIN_DIR:$PATH" \
      LEXIRAY_RELEASE_TEST_MODE=1 \
      LEXIRAY_RELEASE_TEST_HARNESS=1 \
      LEXIRAY_RELEASE_TEST_BIN_DIR="$BIN_DIR" \
      LEXIRAY_RELEASE_STATE_DIR="$STATE_DIR" \
      LEXIRAY_RELEASE_LOCK_FILE="$LOCK_FILE" \
      "$ROOT_DIR/script/release.sh" status "$VERSION" $dry_run 2>&1
  )"
  STATUS_RC=$?
  set -e
}

bash -n "$ROOT_DIR/script/release.sh" "$ROOT_DIR/script/release_identity.sh" \
  "$ROOT_DIR/script/release_capability.sh"
/usr/bin/swiftc -typecheck "$ROOT_DIR/script/release_lock.swift"
/usr/bin/swiftc -typecheck "$ROOT_DIR/script/release_lock_validate.swift"

lock_probe="$WORK_DIR/lock-probe.sh"
printf '#!/usr/bin/env bash\nexit 0\n' >"$lock_probe"
chmod +x "$lock_probe"
for attack in symlink hardlink; do
  attack_dir="$WORK_DIR/$attack-lock"
  attack_target="$WORK_DIR/$attack-target.txt"
  attack_lock="$attack_dir/lock"
  mkdir -p "$attack_dir"
  chmod 700 "$attack_dir"
  printf 'release-lock-sentinel-%s\n' "$attack" >"$attack_target"
  if [[ "$attack" == symlink ]]; then
    ln -s "$attack_target" "$attack_lock"
  else
    ln "$attack_target" "$attack_lock"
  fi
  if /usr/bin/swift "$ROOT_DIR/script/release_lock.swift" --test \
    "$attack_lock" "$lock_probe" >"$WORK_DIR/$attack-lock.out" 2>&1; then
    echo "release lock launcher accepted a $attack lock" >&2
    exit 1
  fi
  [[ "$(<"$attack_target")" == "release-lock-sentinel-$attack" ]] || {
    echo "release lock launcher modified the $attack target" >&2
    exit 1
  }
done
workflow="$ROOT_DIR/.github/workflows/release-build.yml"
rg -F 'repos/$GH_REPOSITORY/commits/main' "$workflow" >/dev/null
rg -F 'repos/$GH_REPOSITORY/commits/$tag' "$workflow" >/dev/null
rg -F 'expected_state_key="$tag-${tag_sha:0:12}"' "$workflow" >/dev/null
rg -F 'INPUT_DISPATCH_ID: ${{ inputs.dispatch_id }}' "$workflow" >/dev/null
rg -F 'run-name: Release Build v${{ inputs.version }} [${{ inputs.state_key }}/${{ inputs.dispatch_id }}]' "$workflow" >/dev/null
rg -F 'ref: ${{ steps.resolve.outputs.sha }}' "$workflow" >/dev/null
rg -F 'uses: actions/upload-artifact@v6' "$workflow" >/dev/null
rg -F 'name: LexiRay-release-${{ inputs.state_key }}-${{ inputs.dispatch_id }}' "$workflow" >/dev/null
rg -F 'WORKFLOW="release-build.yml"' "$ROOT_DIR/script/release.sh" >/dev/null
if rg -F 'codeql.yml' "$workflow" "$ROOT_DIR/script/release.sh" >/dev/null; then
  echo "CodeQL remains a blocking exact-commit release gate" >&2
  exit 1
fi
if rg -F 'LEXIRAY_RELEASE_WORKFLOW' "$ROOT_DIR/script/release.sh" >/dev/null; then
  echo "production release workflow remains environment-overridable" >&2
  exit 1
fi
for forbidden_command in doctor publish; do
  if PATH="$BIN_DIR:$PATH" \
    LEXIRAY_RELEASE_TEST_MODE=1 \
    LEXIRAY_RELEASE_TEST_HARNESS=1 \
    LEXIRAY_RELEASE_TEST_BIN_DIR="$BIN_DIR" \
    LEXIRAY_RELEASE_STATE_DIR="$STATE_DIR" \
    LEXIRAY_RELEASE_LOCK_FILE="$LOCK_FILE" \
    "$ROOT_DIR/script/release.sh" "$forbidden_command" "$VERSION" \
    >"$WORK_DIR/test-$forbidden_command.out" 2>&1; then
    echo "release test mode allowed $forbidden_command" >&2
    exit 1
  fi
  grep -F "restricted to the isolated no-network status harness" \
    "$WORK_DIR/test-$forbidden_command.out" >/dev/null
done
if rg -F 'publish_release.sh' "$workflow" >/dev/null; then
  echo "fallback workflow can publish a public GitHub Release" >&2
  exit 1
fi
if rg -F 'ref: ${{ steps.resolve.outputs.tag }}' "$workflow" >/dev/null; then
  echo "fallback workflow checks out a mutable tag instead of the trusted SHA" >&2
  exit 1
fi
if rg -n '\bsleep\b|show-keychain-info|unlock-keychain' "$ROOT_DIR/script/release.sh" >/dev/null; then
  echo "release state machine contains a polling loop or interactive keychain probe" >&2
  exit 1
fi
receipt_line="$(rg -n '^[[:space:]]+require_release_receipt$' "$ROOT_DIR/script/release.sh" | head -n 1 | cut -d: -f1)"
build_compare_line="$(rg -n 'candidate receipt build is' "$ROOT_DIR/script/release.sh" | head -n 1 | cut -d: -f1)"
[[ -n "$receipt_line" && -n "$build_compare_line" && "$receipt_line" -lt "$build_compare_line" ]] || {
  echo "release doctor compares the build before loading the candidate receipt" >&2
  exit 1
}
rg -F 'release_lock_validate.swift' "$ROOT_DIR/script/release.sh" >/dev/null || {
  echo "release state is not protected by the validated kernel lock" >&2
  exit 1
}
if rg -n 'local -a (validator_arguments|lock_arguments)' "$ROOT_DIR/script/release.sh" >/dev/null; then
  echo "release lock bootstrap still expands an empty array under macOS Bash 3.2 nounset" >&2
  exit 1
fi
rg -F '"$GLOBAL_LOCK_FILE" 9 >/dev/null' "$ROOT_DIR/script/release.sh" >/dev/null || {
  echo "normal release lock validation is not invoked without test arguments" >&2
  exit 1
}
rg -F '"$GLOBAL_LOCK_FILE" "$ROOT_DIR/script/release.sh" "$@"' \
  "$ROOT_DIR/script/release.sh" >/dev/null || {
  echo "normal release lock bootstrap is not invoked without test arguments" >&2
  exit 1
}
rg -F 'git rev-list --parents -n 1 "$TAG_COMMIT"' "$ROOT_DIR/script/release.sh" >/dev/null || {
  echo "release doctor does not validate the tagged release merge topology" >&2
  exit 1
}
rg -F 'must point at a two-parent dev-to-main release merge commit' \
  "$ROOT_DIR/script/release.sh" >/dev/null || {
  echo "release doctor does not fail closed for a non-merge release tag" >&2
  exit 1
}
if rg -F 'rules/branches/main' "$ROOT_DIR/script/release.sh" >/dev/null; then
  echo "release doctor still requires main protection to remain weakened after merge" >&2
  exit 1
fi
rg -F 'kSecUseAuthenticationContext' "$ROOT_DIR/script/probe_release_signing_identity.swift" >/dev/null
rg -F 'interactionNotAllowed = true' "$ROOT_DIR/script/probe_release_signing_identity.swift" >/dev/null
if "$ROOT_DIR/script/generate_release_cert.sh" >"$WORK_DIR/generate.out" 2>&1; then
  echo "release identity generation was not fail-closed" >&2
  exit 1
fi
grep -F "intentionally disabled" "$WORK_DIR/generate.out" >/dev/null
if GITHUB_ACTIONS= "$ROOT_DIR/script/import_release_signing_identity.sh" >"$WORK_DIR/import.out" 2>&1; then
  echo "local shell-based P12 import was not rejected" >&2
  exit 1
fi
grep -F "restricted to GitHub Actions" "$WORK_DIR/import.out" >/dev/null
if "$ROOT_DIR/script/publish_release.sh" 0.4.0 >"$WORK_DIR/direct-publish.out" 2>&1; then
  echo "direct local publication bypassed the release orchestrator" >&2
  exit 1
fi
grep -F "Direct local publication is disabled" "$WORK_DIR/direct-publish.out" >/dev/null
if "$ROOT_DIR/script/package_release_dmg.sh" 0.4.0 >"$WORK_DIR/direct-package.out" 2>&1; then
  echo "direct release packaging bypassed the orchestrator" >&2
  exit 1
fi
grep -F "noninteractive release orchestrator" "$WORK_DIR/direct-package.out" >/dev/null
if "$ROOT_DIR/script/sign_release_app.sh" "$WORK_DIR/Missing.app" >"$WORK_DIR/direct-sign.out" 2>&1; then
  echo "direct release signing bypassed the orchestrator" >&2
  exit 1
fi
grep -F "noninteractive release orchestrator" "$WORK_DIR/direct-sign.out" >/dev/null
if LEXIRAY_RELEASE_ORCHESTRATED=local LEXIRAY_RELEASE_NO_UI=1 \
  "$ROOT_DIR/script/sign_release_app.sh" "$ROOT_DIR/build/release/LexiRay.app" \
  >"$WORK_DIR/forged-sign.out" 2>&1; then
  echo "forged release environment bypassed the locked capability" >&2
  exit 1
fi
grep -F "live, locked release.sh capability" "$WORK_DIR/forged-sign.out" >/dev/null
if LEXIRAY_RELEASE_ORCHESTRATED=local LEXIRAY_RELEASE_NO_UI=1 \
  "$ROOT_DIR/script/package_release_dmg.sh" 0.4.0 >"$WORK_DIR/forged-package.out" 2>&1; then
  echo "forged package environment bypassed the locked capability" >&2
  exit 1
fi
grep -F "live, locked release.sh capability" "$WORK_DIR/forged-package.out" >/dev/null
if GITHUB_ACTIONS= LEXIRAY_RELEASE_ORCHESTRATED=local \
  "$ROOT_DIR/script/publish_release.sh" 0.4.0 >"$WORK_DIR/forged-publish.out" 2>&1; then
  echo "forged publish environment bypassed the locked capability" >&2
  exit 1
fi
grep -F "live, locked release.sh capability" "$WORK_DIR/forged-publish.out" >/dev/null
if GITHUB_ACTIONS=true LEXIRAY_RELEASE_ORCHESTRATED=local \
  "$ROOT_DIR/script/publish_release.sh" 0.4.0 >"$WORK_DIR/github-actions-publish.out" 2>&1; then
  echo "GitHub fallback builder was allowed to publish a public release" >&2
  exit 1
fi
grep -F "GitHub fallback builders may create artifacts, but cannot publish a public release" \
  "$WORK_DIR/github-actions-publish.out" >/dev/null
for helper in package_release_dmg.sh publish_release.sh release_check.sh verify_github_release_assets.sh; do
  set +e
  "$ROOT_DIR/script/$helper" '../outside' >"$WORK_DIR/$helper.out" 2>&1
  helper_rc=$?
  set -e
  if [[ "$helper_rc" -ne 2 ]]; then
    echo "$helper accepted a path-like release version (exit $helper_rc)" >&2
    exit 1
  fi
done
# shellcheck source=../release_identity.sh
source "$ROOT_DIR/script/release_identity.sh"
# shellcheck source=../release_capability.sh
source "$ROOT_DIR/script/release_capability.sh"
if GITHUB_ACTIONS=true \
  GITHUB_REPOSITORY=tensornull/LexiRay \
  GITHUB_EVENT_NAME=workflow_dispatch \
  GITHUB_WORKFLOW_REF=tensornull/LexiRay/.github/workflows/release-build.yml@refs/tags/v9.9.9 \
  GITHUB_REF=refs/heads/main \
  GITHUB_SHA="$COMMIT" \
  lexiray_require_github_fallback_context "$COMMIT"; then
  echo "fallback context accepted a tag workflow ref" >&2
  exit 1
fi
GITHUB_ACTIONS=true \
  GITHUB_REPOSITORY=tensornull/LexiRay \
  GITHUB_EVENT_NAME=workflow_dispatch \
  GITHUB_WORKFLOW_REF=tensornull/LexiRay/.github/workflows/release-build.yml@refs/heads/main \
  GITHUB_REF=refs/heads/main \
  GITHUB_SHA="$COMMIT" \
  lexiray_require_github_fallback_context "$COMMIT"

printf 'release-payload\n' >"$WORK_DIR/LexiRay-$VERSION.dmg"
payload_hash="$(shasum -a 256 "$WORK_DIR/LexiRay-$VERSION.dmg" | awk '{print $1}')"
printf '%s  LexiRay-%s.dmg\n' "$payload_hash" "$VERSION" >"$WORK_DIR/release.sha256"
lexiray_verify_sha256_file \
  "$WORK_DIR/release.sha256" \
  "$WORK_DIR/LexiRay-$VERSION.dmg" \
  "LexiRay-$VERSION.dmg"
printf '%s  ../../etc/passwd\n' "$payload_hash" >"$WORK_DIR/release.sha256"
if lexiray_verify_sha256_file \
  "$WORK_DIR/release.sha256" \
  "$WORK_DIR/LexiRay-$VERSION.dmg" \
  "LexiRay-$VERSION.dmg"; then
  echo "checksum parser accepted a different/path-traversing payload name" >&2
  exit 1
fi

write_state
run_status pending
[[ "$STATUS_RC" -eq 1 ]]
grep -F "No fallback dispatch is recorded" <<<"$STATUS_OUTPUT" >/dev/null

write_state uncertain
run_status query_error
[[ "$STATUS_RC" -eq 75 ]]
grep -F "workflow lookup is temporarily unavailable" <<<"$STATUS_OUTPUT" >/dev/null
grep -F "fallback_dispatch=uncertain" "$STATE_FILE" >/dev/null

write_state complete
run_status dispatch_query
[[ "$STATUS_RC" -eq 75 ]]
grep -F "no new workflow was dispatched" <<<"$STATUS_OUTPUT" >/dev/null
if grep -F "workflow_run_id=" "$STATE_FILE" >/dev/null; then
  echo "fallback lookup rebound a dispatch to an unrelated run" >&2
  exit 1
fi

write_state uncertain
printf 'fallback_dispatch_started_epoch=%s\n' "$(( $(date +%s) - 301 ))" >>"$STATE_FILE"
run_status pending
[[ "$STATUS_RC" -eq 75 ]]
grep -F "dispatch remains uncertain" <<<"$STATUS_OUTPUT" >/dev/null
grep -F "fallback_dispatch=uncertain" "$STATE_FILE" >/dev/null
if grep -F "fallback_dispatch=failed" "$STATE_FILE" >/dev/null; then
  echo "workflow visibility timeout incorrectly became retryable failure" >&2
  exit 1
fi

ready_file="$WORK_DIR/release-lock-ready"
release_fifo="$WORK_DIR/release-lock-release"
mkfifo "$release_fifo"
(
  exec 8>"$LOCK_FILE"
  /usr/bin/lockf -s -t 0 8
  touch "$ready_file"
  read -r _ <"$release_fifo"
) &
lock_holder=$!
for _ in {1..50}; do
  [[ -f "$ready_file" ]] && break
  /bin/sleep 0.02
done
[[ -f "$ready_file" ]]
run_status pending
[[ "$STATUS_RC" -eq 1 ]]
grep -F "Another release command is active" <<<"$STATUS_OUTPUT" >/dev/null
printf '%s\n' release >"$release_fifo"
wait "$lock_holder" >/dev/null 2>&1 || true

write_state complete 999
run_status pending
[[ "$STATUS_RC" -eq 75 ]]
grep -F "fallback is in_progress: https://example.invalid/run/999" <<<"$STATUS_OUTPUT" >/dev/null
grep -F "workflow_url=https://example.invalid/run/999" "$STATE_FILE" >/dev/null

write_state complete 999
run_status failure
[[ "$STATUS_RC" -eq 1 ]]
grep -F "fallback failed (failure)" <<<"$STATUS_OUTPUT" >/dev/null
grep -F "MOCK_FAILED_STEP" <<<"$STATUS_OUTPUT" >/dev/null
grep -F "fallback_dispatch=failed" "$STATE_FILE" >/dev/null
grep -F "last_failed_run_id=999" "$STATE_FILE" >/dev/null

write_state "" "" "$STATE_KEY" local
run_status assets --dry-run
[[ "$STATUS_RC" -eq 0 ]]
grep -F "would download and verify LexiRay-$VERSION.dmg" <<<"$STATUS_OUTPUT" >/dev/null
if grep -F "release=complete" "$STATE_FILE" >/dev/null; then
  echo "dry-run status mutated release state" >&2
  exit 1
fi

write_state complete 999 wrong-correlation-key
run_status pending
[[ "$STATUS_RC" -eq 1 ]]
grep -F "correlation-key mismatch" <<<"$STATUS_OUTPUT" >/dev/null

echo "RELEASE_FLOW_TEST_PASS"

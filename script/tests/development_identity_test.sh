#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/lexiray-development-identity.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT
SECURITY_MOCK="$TMP_ROOT/security"
SWIFT_MOCK="$TMP_ROOT/swift"
CALL_LOG="$TMP_ROOT/calls.log"

cat >"$SECURITY_MOCK" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "security $*" >>"$MOCK_CALL_LOG"
case "$1:$MOCK_MODE" in
  find-identity:keychain-invisible|find-certificate:keychain-invisible) exit 45 ;;
  find-identity:correct|find-identity:duplicate|find-identity:private-fail)
    echo '  1) B665AB9A2956DDD3C2712669E4DA0DBE30DA084D "LexiRay Local Development"'
    echo '     1 valid identities found'
    ;;
  find-identity:wrong)
    echo '  1) E23C5DCED210005F4EFBA6F661E4C1A83FA0357F "LexiRay Local Development"'
    ;;
  find-identity:missing) exit 0 ;;
  find-certificate:correct|find-certificate:private-fail)
    echo 'SHA-256 hash: 77C74E4D76C7A7AE0D0FF77D5C4AA928E0FE75CA463BF7B5FC6D0C9E08F6D356'
    echo 'SHA-1 hash: B665AB9A2956DDD3C2712669E4DA0DBE30DA084D'
    ;;
  find-certificate:duplicate)
    echo 'SHA-256 hash: C23A51695EEFAA6FECE16DA8594915AC5A98208141CBD5BD2516AA9905CB46B5'
    echo 'SHA-1 hash: E23C5DCED210005F4EFBA6F661E4C1A83FA0357F'
    echo 'SHA-256 hash: 77C74E4D76C7A7AE0D0FF77D5C4AA928E0FE75CA463BF7B5FC6D0C9E08F6D356'
    echo 'SHA-1 hash: B665AB9A2956DDD3C2712669E4DA0DBE30DA084D'
    ;;
  find-certificate:wrong)
    echo 'SHA-256 hash: C23A51695EEFAA6FECE16DA8594915AC5A98208141CBD5BD2516AA9905CB46B5'
    echo 'SHA-1 hash: E23C5DCED210005F4EFBA6F661E4C1A83FA0357F'
    ;;
  find-certificate:missing) exit 0 ;;
  *) exit 92 ;;
esac
EOF

cat >"$SWIFT_MOCK" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "swift $*" >>"$MOCK_CALL_LOG"
[[ "$MOCK_MODE" != private-fail ]]
EOF
chmod +x "$SECURITY_MOCK" "$SWIFT_MOCK"

run_identity() {
  MOCK_MODE="$1" \
    MOCK_CALL_LOG="$CALL_LOG" \
    LEXIRAY_DEVELOPMENT_SECURITY_TOOL="$SECURITY_MOCK" \
    LEXIRAY_DEVELOPMENT_SWIFT_TOOL="$SWIFT_MOCK" \
    LEXIRAY_CODE_SIGN_KEYCHAIN="$TMP_ROOT/login.keychain-db" \
    "$ROOT_DIR/script/development_identity.sh" "$2"
}

[[ "$(run_identity correct verify)" == B665AB9A2956DDD3C2712669E4DA0DBE30DA084D ]]
run_identity duplicate verify >/dev/null
run_identity duplicate doctor >"$TMP_ROOT/doctor.log"
rg -F 'Same-name certificates: 2' "$TMP_ROOT/doctor.log" >/dev/null
rg -F 'DEVELOPMENT_IDENTITY_PASS' "$TMP_ROOT/doctor.log" >/dev/null

for mode in missing wrong private-fail keychain-invisible; do
  if run_identity "$mode" verify >"$TMP_ROOT/$mode.log" 2>&1; then
    echo "development identity verify accepted $mode" >&2
    exit 1
  fi
  rg -F 'Run: ./script/development_identity.sh doctor' "$TMP_ROOT/$mode.log" >/dev/null
done

if rg -n 'security (import|add-trusted-cert)|openssl (req|pkcs12)' "$CALL_LOG" >/dev/null; then
  echo "normal development identity verification attempted a mutation" >&2
  exit 1
fi
if rg -n 'security (import|add-trusted-cert)|openssl (req|pkcs12)' \
  "$ROOT_DIR/script/ensure_local_codesign_identity.sh" \
  "$ROOT_DIR/script/development_identity.sh" >/dev/null; then
  echo "normal development identity scripts contain certificate creation/import paths" >&2
  exit 1
fi

echo "DEVELOPMENT_IDENTITY_TEST_PASS"

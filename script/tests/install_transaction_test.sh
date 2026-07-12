#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/lexiray-install-transaction.XXXXXX")"
TMP_ROOT="$(cd "$TMP_ROOT" && pwd -P)"
trap 'rm -rf "$TMP_ROOT"' EXIT

LEXIRAY_INSTALL_LIBRARY_ONLY=1 source "$ROOT_DIR/script/install_applications.sh"
register_app() { :; }

original_process_match="$(declare -f installed_acceptance_process_matches)"
pgrep() { printf '%s\n' 4101 4102; }
installed_acceptance_process_matches() {
  [[ "$1" == 4102 && "$2" == /Applications/LexiRay.app/Contents/MacOS/LexiRay &&
    "$3" == /tmp/acceptance-root && "$4" == io.github.tensornull.lexiray.acceptance.test ]]
}
[[ "$(find_installed_acceptance_pid \
  /Applications/LexiRay.app/Contents/MacOS/LexiRay \
  /tmp/acceptance-root \
  io.github.tensornull.lexiray.acceptance.test)" == 4102 ]] || {
  echo "installer did not select the exact acceptance-profile process" >&2
  exit 1
}
unset -f pgrep installed_acceptance_process_matches
eval "$original_process_match"

computer_use_fixture="$ROOT_DIR/script/ui/fixtures/computer-use-providers.json"
[[ "$(/usr/bin/plutil -extract preferredProvider raw -n -- "$computer_use_fixture")" == mock &&
  "$(/usr/bin/plutil -extract providers.mock.providerID raw -n -- "$computer_use_fixture")" == mock &&
  "$(/usr/bin/plutil -extract providers.mock.isEnabled raw -n -- "$computer_use_fixture")" == true ]] || {
  echo "installed Computer Use fixture does not provide the enabled mock provider" >&2
  exit 1
}
grep -F 'cp "$ROOT_DIR/script/ui/fixtures/computer-use-providers.json" "$acceptance_root/providers.json"' \
  "$ROOT_DIR/script/install_applications.sh" >/dev/null || {
  echo "installer does not seed the dedicated Computer Use provider fixture" >&2
  exit 1
}
if grep -F 'rm -rf "$acceptance_root"' "$ROOT_DIR/script/install_applications.sh" >/dev/null; then
  echo "installer still deletes a path-derived acceptance root" >&2
  exit 1
fi

test_fingerprint="$(printf 'a%.0s' {1..64})"
acceptance_workspace="$TMP_ROOT/acceptance-workspace"
mkdir "$acceptance_workspace"
first_acceptance_transaction="00000000-0000-4000-8000-000000000111"
create_installed_acceptance_root \
  "$acceptance_workspace" "$test_fingerprint" "$first_acceptance_transaction"
expected_acceptance_root="$(installed_acceptance_root_path \
  "$acceptance_workspace" "$test_fingerprint" "$first_acceptance_transaction")"
[[ "$ACCEPTANCE_ROOT" == "$expected_acceptance_root" &&
  -d "$ACCEPTANCE_ROOT" && ! -L "$ACCEPTANCE_ROOT" &&
  "$(/usr/bin/stat -f '%Lp' "$ACCEPTANCE_ROOT")" == 700 ]]

preexisting_transaction="00000000-0000-4000-8000-000000000112"
preexisting_root="$(installed_acceptance_root_path \
  "$acceptance_workspace" "$test_fingerprint" "$preexisting_transaction")"
mkdir "$preexisting_root"
printf 'preserve acceptance data\n' >"$preexisting_root/sentinel"
if (create_installed_acceptance_root \
  "$acceptance_workspace" "$test_fingerprint" "$preexisting_transaction") \
  >"$TMP_ROOT/preexisting-acceptance.out" 2>&1; then
  echo "installer accepted a preexisting acceptance root" >&2
  exit 1
fi
[[ "$(<"$preexisting_root/sentinel")" == "preserve acceptance data" ]]

symlink_transaction="00000000-0000-4000-8000-000000000113"
symlink_root="$(installed_acceptance_root_path \
  "$acceptance_workspace" "$test_fingerprint" "$symlink_transaction")"
symlink_target="$TMP_ROOT/acceptance-symlink-target"
mkdir "$symlink_target"
printf 'preserve target\n' >"$symlink_target/sentinel"
ln -s "$symlink_target" "$symlink_root"
if (create_installed_acceptance_root \
  "$acceptance_workspace" "$test_fingerprint" "$symlink_transaction") \
  >"$TMP_ROOT/symlink-acceptance.out" 2>&1; then
  echo "installer accepted a symlinked acceptance root" >&2
  exit 1
fi
[[ -L "$symlink_root" && "$(<"$symlink_target/sentinel")" == "preserve target" ]]

stop_block="$(sed -n '/^stop_lexiray_apps()/,/^}/p' "$ROOT_DIR/script/install_applications.sh")"
grep -F 'local installed_executable="$APP_DST/Contents/MacOS/$APP_NAME"' <<<"$stop_block" >/dev/null || {
  echo "installer process cleanup is not bound to the canonical Applications executable" >&2
  exit 1
}
for trap_line in "trap 'exit 129' HUP" "trap 'exit 130' INT" "trap 'exit 143' TERM"; do
  grep -F "$trap_line" "$ROOT_DIR/script/install_applications.sh" >/dev/null
done

test_identity_hash() {
  local kind="$1"
  local app="$2"
  printf '%s:%s' "$kind" "$(bundle_executable_sha256 "$app")" |
    /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}'
}

# Ad-hoc test bundles have no leaf certificate. These deterministic test
# identity providers exercise the transaction fields while codesign verification
# remains real and catches sealed-resource tampering.
bundle_certificate_sha256() { test_identity_hash certificate "$1"; }
bundle_requirement_sha256() { test_identity_hash requirement "$1"; }
bundle_entitlements_sha256() { test_identity_hash entitlements "$1"; }

VALID_INSTALLED_TRANSACTION=""
installed_transaction_valid() {
  [[ "$1" == "$VALID_INSTALLED_TRANSACTION" && "$2" == "$APP_DST" ]]
}

make_bundle() {
  local path="$1"
  local executable_source="$2"
  mkdir -p "$path/Contents/MacOS" "$path/Contents/Resources"
  cp "$executable_source" "$path/Contents/MacOS/TestApp"
  printf 'sealed fixture\n' >"$path/Contents/Resources/data.txt"
  /usr/bin/plutil -create xml1 "$path/Contents/Info.plist"
  /usr/bin/plutil -insert CFBundleExecutable -string TestApp -- "$path/Contents/Info.plist"
  /usr/bin/plutil -insert CFBundleIdentifier -string "io.github.tensornull.lexiray.install-test" -- "$path/Contents/Info.plist"
  /usr/bin/plutil -insert CFBundlePackageType -string APPL -- "$path/Contents/Info.plist"
  /usr/bin/codesign --force --sign - "$path" >/dev/null 2>&1
}

capture_identity() {
  local app="$1"
  ID_CDHASH="$(bundle_cdhash "$app")"
  ID_EXECUTABLE="$(bundle_executable_sha256 "$app")"
  ID_CERTIFICATE="$(bundle_certificate_sha256 "$app")"
  ID_REQUIREMENT="$(bundle_requirement_sha256 "$app")"
  ID_ENTITLEMENTS="$(bundle_entitlements_sha256 "$app")"
  ID_DEVICE="$(bundle_root_device "$app")"
  ID_INODE="$(bundle_root_inode "$app")"
}

exchange_with_current_destination() {
  local source="$1"
  local destination="$2"
  atomic_replace \
    "$source" "$destination" existing \
    "$(bundle_root_device "$destination")" "$(bundle_root_inode "$destination")"
}

move_to_absent_destination() {
  atomic_replace "$1" "$2" absent
}

reset_paths() {
  local name="$1"
  case_root="$TMP_ROOT/$name"
  rm -rf "$case_root"
  mkdir -p "$case_root"
  APP_DST="$case_root/LexiRay.app"
  TRANSACTION_ID="00000000-0000-4000-8000-000000000123"
  STAGING="$case_root/LexiRay.app.agent-installing-$TRANSACTION_ID"
  TRANSACTION_FILE="$case_root/install-transaction.plist"
  VALID_INSTALLED_TRANSACTION=""
  SWAP_POSSIBLE=0
}

reset_paths destination-shape
install_destination_is_replaceable "$APP_DST"
printf 'preserve me\n' >"$APP_DST"
if install_destination_is_replaceable "$APP_DST"; then
  echo "installer accepted a non-directory destination" >&2
  exit 1
fi
[[ "$(<"$APP_DST")" == "preserve me" ]]
rm -f "$APP_DST"
mkdir -p "$case_root/real-app"
ln -s "$case_root/real-app" "$APP_DST"
if install_destination_is_replaceable "$APP_DST"; then
  echo "installer accepted a symlinked destination" >&2
  exit 1
fi
[[ -L "$APP_DST" && -d "$case_root/real-app" ]]
rm -f "$APP_DST"
make_bundle "$APP_DST" /usr/bin/true
install_destination_is_replaceable "$APP_DST"

grep -F 'install_destination_is_replaceable "$APP_DST" ||' \
  "$ROOT_DIR/script/install_applications.sh" >/dev/null || {
  echo "installer does not validate the destination before swapping" >&2
  exit 1
}

write_test_transaction() {
  local had_previous="$1"
  capture_identity "$STAGING"
  NEW_CDHASH="$ID_CDHASH"
  NEW_EXECUTABLE="$ID_EXECUTABLE"
  NEW_CERTIFICATE="$ID_CERTIFICATE"
  NEW_REQUIREMENT="$ID_REQUIREMENT"
  NEW_ENTITLEMENTS="$ID_ENTITLEMENTS"
  NEW_DEVICE="$ID_DEVICE"
  NEW_INODE="$ID_INODE"
  OLD_CDHASH=""
  OLD_EXECUTABLE=""
  OLD_CERTIFICATE=""
  OLD_REQUIREMENT=""
  OLD_ENTITLEMENTS=""
  OLD_DEVICE=""
  OLD_INODE=""
  if [[ "$had_previous" == true ]]; then
    capture_identity "$APP_DST"
    OLD_CDHASH="$ID_CDHASH"
    OLD_EXECUTABLE="$ID_EXECUTABLE"
    OLD_CERTIFICATE="$ID_CERTIFICATE"
    OLD_REQUIREMENT="$ID_REQUIREMENT"
    OLD_ENTITLEMENTS="$ID_ENTITLEMENTS"
    OLD_DEVICE="$ID_DEVICE"
    OLD_INODE="$ID_INODE"
  fi
  write_transaction prepared "$had_previous" \
    "$NEW_CDHASH" "$NEW_EXECUTABLE" "$NEW_CERTIFICATE" "$NEW_REQUIREMENT" "$NEW_ENTITLEMENTS" \
    "$NEW_DEVICE" "$NEW_INODE" \
    "$OLD_CDHASH" "$OLD_EXECUTABLE" "$OLD_CERTIFICATE" "$OLD_REQUIREMENT" "$OLD_ENTITLEMENTS" \
    "$OLD_DEVICE" "$OLD_INODE"
}

assert_old_restored() {
  bundle_matches_identity \
    "$APP_DST" "$OLD_CDHASH" "$OLD_EXECUTABLE" "$OLD_CERTIFICATE" \
    "$OLD_REQUIREMENT" "$OLD_ENTITLEMENTS" "$OLD_DEVICE" "$OLD_INODE"
  [[ ! -e "$STAGING" && ! -e "$TRANSACTION_FILE" ]]
}

assert_candidate_installed() {
  bundle_matches_identity \
    "$APP_DST" "$NEW_CDHASH" "$NEW_EXECUTABLE" "$NEW_CERTIFICATE" \
    "$NEW_REQUIREMENT" "$NEW_ENTITLEMENTS" "$NEW_DEVICE" "$NEW_INODE"
  [[ ! -e "$STAGING" && ! -e "$TRANSACTION_FILE" ]]
}

reset_paths pre-swap
make_bundle "$APP_DST" /usr/bin/true
make_bundle "$STAGING" /bin/echo
write_test_transaction true
recover_interrupted_install
assert_old_restored

reset_paths post-swap
make_bundle "$APP_DST" /usr/bin/true
make_bundle "$STAGING" /bin/echo
write_test_transaction true
exchange_with_current_destination "$STAGING" "$APP_DST"
recover_interrupted_install
assert_old_restored

reset_paths validated-with-receipt
make_bundle "$APP_DST" /usr/bin/true
make_bundle "$STAGING" /bin/echo
write_test_transaction true
exchange_with_current_destination "$STAGING" "$APP_DST"
set_transaction_state validated
VALID_INSTALLED_TRANSACTION="$TRANSACTION_ID"
recover_interrupted_install
assert_candidate_installed

reset_paths validated-without-receipt
make_bundle "$APP_DST" /usr/bin/true
make_bundle "$STAGING" /bin/echo
write_test_transaction true
exchange_with_current_destination "$STAGING" "$APP_DST"
set_transaction_state validated
recover_interrupted_install
assert_old_restored

reset_paths injected-before
make_bundle "$APP_DST" /usr/bin/true
make_bundle "$STAGING" /bin/echo
write_test_transaction true
if LEXIRAY_INSTALL_TEST_MODE=1 LEXIRAY_ATOMIC_REPLACE_TEST_FAULT=before \
  exchange_with_current_destination "$STAGING" "$APP_DST" >/dev/null 2>&1; then
  echo "before-swap fault injection unexpectedly succeeded" >&2
  exit 1
fi
recover_interrupted_install
assert_old_restored

reset_paths injected-after
make_bundle "$APP_DST" /usr/bin/true
make_bundle "$STAGING" /bin/echo
write_test_transaction true
if LEXIRAY_INSTALL_TEST_MODE=1 LEXIRAY_ATOMIC_REPLACE_TEST_FAULT=after \
  exchange_with_current_destination "$STAGING" "$APP_DST" >/dev/null 2>&1; then
  echo "after-swap fault injection unexpectedly succeeded" >&2
  exit 1
fi
recover_interrupted_install
assert_old_restored

reset_paths first-install-before
make_bundle "$STAGING" /bin/echo
write_test_transaction false
recover_interrupted_install
[[ ! -e "$APP_DST" && ! -e "$STAGING" && ! -e "$TRANSACTION_FILE" ]]

# The destination can appear after the shell-level guard. RENAME_EXCL must
# reject it in the same syscall that would otherwise publish the candidate.
reset_paths first-install-concurrent-destination
make_bundle "$STAGING" /bin/echo
write_test_transaction false
printf 'preserve concurrent object\n' >"$APP_DST"
if move_to_absent_destination "$STAGING" "$APP_DST" >"$case_root/exchange.out" 2>&1; then
  echo "first-install exchange replaced a concurrent destination" >&2
  exit 1
fi
[[ "$(<"$APP_DST")" == "preserve concurrent object" &&
  -d "$STAGING" && -f "$TRANSACTION_FILE" ]]

# A replacement of an existing app root after its identity was recorded must
# be rejected without moving either object.
reset_paths existing-destination-identity-race
make_bundle "$APP_DST" /usr/bin/true
make_bundle "$STAGING" /bin/echo
write_test_transaction true
rm -rf "$APP_DST"
make_bundle "$APP_DST" /usr/bin/false
unknown_device="$(bundle_root_device "$APP_DST")"
unknown_inode="$(bundle_root_inode "$APP_DST")"
if atomic_replace \
  "$STAGING" "$APP_DST" existing "$OLD_DEVICE" "$OLD_INODE" \
  >"$case_root/exchange.out" 2>&1; then
  echo "atomic exchange accepted a changed destination identity" >&2
  exit 1
fi
bundle_matches_object "$APP_DST" "$unknown_device" "$unknown_inode"
bundle_matches_object "$STAGING" "$NEW_DEVICE" "$NEW_INODE"
[[ -f "$TRANSACTION_FILE" ]]

reset_paths first-install-after
make_bundle "$STAGING" /bin/echo
write_test_transaction false
move_to_absent_destination "$STAGING" "$APP_DST"
recover_interrupted_install
[[ ! -e "$APP_DST" && ! -e "$STAGING" && ! -e "$TRANSACTION_FILE" ]]

reset_paths first-install-validated
make_bundle "$STAGING" /bin/echo
write_test_transaction false
move_to_absent_destination "$STAGING" "$APP_DST"
set_transaction_state validated
VALID_INSTALLED_TRANSACTION="$TRANSACTION_ID"
recover_interrupted_install
assert_candidate_installed

# Once cleanup intent is durable, missing or partially deleted staging content
# must be disposable without requiring its signature to remain verifiable.
reset_paths rollback-cleanup-resume
make_bundle "$APP_DST" /usr/bin/true
make_bundle "$STAGING" /bin/echo
write_test_transaction true
set_transaction_state rollback_cleanup
rm -rf "$STAGING/Contents/MacOS"
recover_interrupted_install
assert_old_restored

reset_paths commit-cleanup-resume
make_bundle "$APP_DST" /usr/bin/true
make_bundle "$STAGING" /bin/echo
write_test_transaction true
exchange_with_current_destination "$STAGING" "$APP_DST"
set_transaction_state commit_cleanup
VALID_INSTALLED_TRANSACTION="$TRANSACTION_ID"
rm -rf "$STAGING/Contents/MacOS"
recover_interrupted_install
assert_candidate_installed

reset_paths first-install-cleanup-resume
make_bundle "$STAGING" /bin/echo
write_test_transaction false
move_to_absent_destination "$STAGING" "$APP_DST"
# rollback_cleanup is entered only after the candidate is quarantined back to
# the transaction-owned staging inode.
move_to_absent_destination "$APP_DST" "$STAGING"
set_transaction_state rollback_cleanup
rm -rf "$STAGING/Contents/Resources"
recover_interrupted_install
[[ ! -e "$APP_DST" && ! -e "$STAGING" && ! -e "$TRANSACTION_FILE" ]]

# A later app at the canonical destination is never removed by first-install
# cleanup. The quarantined candidate and marker remain for manual inspection.
reset_paths first-install-unknown-destination
make_bundle "$STAGING" /bin/echo
write_test_transaction false
set_transaction_state rollback_cleanup
make_bundle "$APP_DST" /usr/bin/false
if recover_interrupted_install >"$case_root/recovery.out" 2>&1; then
  echo "first-install cleanup deleted an unknown destination" >&2
  exit 1
fi
[[ -d "$APP_DST" && -d "$STAGING" && -f "$TRANSACTION_FILE" ]]
grep -F "unknown destination" "$case_root/recovery.out" >/dev/null

# Exact app bytes are insufficient for deletion after validation: replacing the
# staging root changes its inode and must preserve both objects.
reset_paths replaced-staging-object
make_bundle "$APP_DST" /usr/bin/true
make_bundle "$STAGING" /bin/echo
write_test_transaction true
exchange_with_current_destination "$STAGING" "$APP_DST"
set_transaction_state validated
VALID_INSTALLED_TRANSACTION="$TRANSACTION_ID"
rm -rf "$STAGING"
make_bundle "$STAGING" /usr/bin/true
if recover_interrupted_install >"$case_root/recovery.out" 2>&1; then
  echo "replacement staging inode was deleted" >&2
  exit 1
fi
[[ -d "$APP_DST" && -d "$STAGING" && -f "$TRANSACTION_FILE" ]]
grep -F "transaction artifacts were preserved" "$case_root/recovery.out" >/dev/null

# Marker writes must reject a directory destination rather than allowing mv to
# place a temporary plist inside it.
reset_paths marker-directory
make_bundle "$STAGING" /bin/echo
mkdir "$TRANSACTION_FILE"
if (write_test_transaction false) >"$case_root/write.out" 2>&1; then
  echo "transaction writer accepted a marker directory" >&2
  exit 1
fi
[[ -d "$TRANSACTION_FILE" ]]
if find "$TRANSACTION_FILE" -mindepth 1 -print -quit | grep -q .; then
  echo "transaction temporary file was moved inside the marker directory" >&2
  exit 1
fi

# Every parent component must be canonical; a symlinked transaction/App parent
# is rejected before a marker is created.
symlink_case="$TMP_ROOT/symlink-parent"
mkdir -p "$symlink_case/real"
ln -s "$symlink_case/real" "$symlink_case/link"
APP_DST="$symlink_case/link/LexiRay.app"
TRANSACTION_ID="00000000-0000-4000-8000-000000000123"
STAGING="$APP_DST.agent-installing-$TRANSACTION_ID"
TRANSACTION_FILE="$symlink_case/link/install-transaction.plist"
make_bundle "$STAGING" /bin/echo
if (write_test_transaction false) >"$symlink_case/write.out" 2>&1; then
  echo "transaction writer accepted a symlinked parent" >&2
  exit 1
fi
[[ ! -e "$symlink_case/real/install-transaction.plist" ]]

# Once swap becomes possible, losing the marker must preserve the object at
# staging; it may be the user's previous installed app.
reset_paths marker-disappears-after-swap
make_bundle "$APP_DST" /usr/bin/true
make_bundle "$STAGING" /bin/echo
write_test_transaction true
SWAP_POSSIBLE=1
exchange_with_current_destination "$STAGING" "$APP_DST"
rm -f "$TRANSACTION_FILE"
if (rollback) >"$case_root/rollback.out" 2>&1; then
  echo "rollback accepted a missing post-swap transaction marker" >&2
  exit 1
fi
[[ -d "$APP_DST" && -d "$STAGING" && ! -e "$TRANSACTION_FILE" ]]
grep -F "preserving all app objects" "$case_root/rollback.out" >/dev/null

# A bundle whose sealed resources changed must never match the transaction even
# when its embedded CDHash and executable bytes are unchanged.
reset_paths tampered-candidate
make_bundle "$APP_DST" /usr/bin/true
make_bundle "$STAGING" /bin/echo
write_test_transaction true
exchange_with_current_destination "$STAGING" "$APP_DST"
printf 'tampered\n' >"$APP_DST/Contents/Resources/data.txt"
if recover_interrupted_install >"$case_root/recovery.out" 2>&1; then
  echo "signature-invalid candidate was reconciled destructively" >&2
  exit 1
fi
[[ -d "$APP_DST" && -d "$STAGING" && -f "$TRANSACTION_FILE" ]]
grep -F "transaction artifacts were preserved" "$case_root/recovery.out" >/dev/null

reset_paths ambiguous
make_bundle "$APP_DST" /usr/bin/true
make_bundle "$STAGING" /bin/echo
write_test_transaction true
make_bundle "$APP_DST" /usr/bin/false
if recover_interrupted_install >"$case_root/recovery.out" 2>&1; then
  echo "ambiguous install transaction was reconciled destructively" >&2
  exit 1
fi
[[ -d "$APP_DST" && -d "$STAGING" && -f "$TRANSACTION_FILE" ]]
grep -F "transaction artifacts were preserved" "$case_root/recovery.out" >/dev/null

# EXIT/HUP/INT/TERM all converge on the same rollback transaction. The signal
# handlers are asserted above; ordinary EXIT exercises that shared path.
reset_paths exit-rollback
make_bundle "$APP_DST" /usr/bin/true
make_bundle "$STAGING" /bin/echo
write_test_transaction true
set +e
(trap rollback EXIT; exit 42) >/dev/null 2>&1
set -e
assert_old_restored

# SIGKILL cannot run a trap. This is the exact durable post-swap state left for
# the next installer process, which must recover it without process cooperation.
reset_paths sigkill-resume
make_bundle "$APP_DST" /usr/bin/true
make_bundle "$STAGING" /bin/echo
write_test_transaction true
exchange_with_current_destination "$STAGING" "$APP_DST"
recover_interrupted_install
assert_old_restored

LOCK_FILE="$TMP_ROOT/install.lock"
lock_probe="$TMP_ROOT/install-lock-probe.sh"
printf '#!/usr/bin/env bash\nexit 0\n' >"$lock_probe"
chmod +x "$lock_probe"
for attack in symlink hardlink; do
  attack_target="$TMP_ROOT/$attack-install-lock-target"
  attack_lock="$TMP_ROOT/$attack-install.lock"
  printf 'install-lock-sentinel-%s\n' "$attack" >"$attack_target"
  if [[ "$attack" == symlink ]]; then
    ln -s "$attack_target" "$attack_lock"
  else
    ln "$attack_target" "$attack_lock"
  fi
  if /usr/bin/swift "$ROOT_DIR/script/install_lock.swift" --test \
    "$attack_lock" "$lock_probe" >"$TMP_ROOT/$attack-install-lock.out" 2>&1; then
    echo "install lock launcher accepted a $attack lock" >&2
    exit 1
  fi
  [[ "$(<"$attack_target")" == "install-lock-sentinel-$attack" ]] || {
    echo "install lock launcher modified the $attack target" >&2
    exit 1
  }
done

ready_file="$TMP_ROOT/install-lock-ready"
release_fifo="$TMP_ROOT/install-lock-release"
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
if (acquire_install_lock) >"$TMP_ROOT/lock.out" 2>&1; then
  echo "install lock allowed concurrent ownership" >&2
  printf '%s\n' release >"$release_fifo"
  wait "$lock_holder" >/dev/null 2>&1 || true
  exit 1
fi
grep -F "another LexiRay installation is active" "$TMP_ROOT/lock.out" >/dev/null
printf '%s\n' release >"$release_fifo"
wait "$lock_holder" >/dev/null 2>&1 || true

# The production validator rejects a forged inherited descriptor and obtains
# the lock on the parent's shared open-file description when it is valid.
validator_lock="$TMP_ROOT/validator.lock"
exec 7>"$validator_lock"
/usr/bin/swift "$ROOT_DIR/script/install_lock_validate.swift" --test "$validator_lock" 7
validator_alias="$TMP_ROOT/validator-hardlink.lock"
ln "$validator_lock" "$validator_alias"
if /usr/bin/swift "$ROOT_DIR/script/install_lock_validate.swift" --test "$validator_lock" 7 \
  >"$TMP_ROOT/hardlinked-validator.out" 2>&1; then
  echo "install lock validator accepted a hard-linked lock" >&2
  exit 1
fi
grep -F "does not identify" "$TMP_ROOT/hardlinked-validator.out" >/dev/null
rm "$validator_alias"
exec 6</dev/null
if /usr/bin/swift "$ROOT_DIR/script/install_lock_validate.swift" --test "$validator_lock" 6 \
  >"$TMP_ROOT/forged-fd.out" 2>&1; then
  echo "install lock validator accepted a forged /dev/null descriptor" >&2
  exit 1
fi
grep -F "does not identify" "$TMP_ROOT/forged-fd.out" >/dev/null
if (
  exec 8<>"$validator_lock"
  /usr/bin/swift "$ROOT_DIR/script/install_lock_validate.swift" --test "$validator_lock" 8
) >"$TMP_ROOT/second-lock.out" 2>&1; then
  echo "install lock validator allowed independent concurrent ownership" >&2
  exit 1
fi
grep -F "another LexiRay installation is active" "$TMP_ROOT/second-lock.out" >/dev/null
exec 6<&-
exec 7>&-

echo "INSTALL_TRANSACTION_TEST_PASS"

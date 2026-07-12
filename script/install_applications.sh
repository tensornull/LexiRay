#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=release_identity.sh
source "$ROOT_DIR/script/release_identity.sh"
APP_NAME="LexiRay"
APP_DST="/Applications/$APP_NAME.app"
TRANSACTION_ID=""
STAGING=""
STAGING_DEVICE=""
STAGING_INODE=""
ACCEPTANCE_ROOT=""
ACCEPTANCE_ROOT_DEVICE=""
ACCEPTANCE_ROOT_INODE=""
RECEIPT_TOOL="$ROOT_DIR/script/acceptance_receipt.sh"
EVIDENCE_HELPER="$ROOT_DIR/script/acceptance_evidence.swift"
INSTALL_LIBRARY_ONLY="${LEXIRAY_INSTALL_LIBRARY_ONLY:-0}"
if [[ "$INSTALL_LIBRARY_ONLY" == 1 ]]; then
  TRANSACTION_FILE="${LEXIRAY_INSTALL_TRANSACTION_FILE:-$ROOT_DIR/build/acceptance/install-transaction.plist}"
  LOCK_FILE="${LEXIRAY_INSTALL_LOCK_FILE:-$ROOT_DIR/build/acceptance/install.lock}"
else
  TRANSACTION_FILE="/Applications/.io.github.tensornull.lexiray.install.transaction.plist"
  LOCK_FILE="/Applications/.io.github.tensornull.lexiray.install.lock"
fi
LOCK_HELD=0
SWAP_POSSIBLE=0

die() {
  echo "INSTALL_ERROR: $*" >&2
  exit 1
}

running_builds() {
  pgrep -fl 'xcodebuild|script/ci_local\.sh|script/verify\.sh' || true
}

stop_lexiray_apps() {
  local installed_executable="$APP_DST/Contents/MacOS/$APP_NAME"
  (pgrep -x "$APP_NAME" || true) | while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    case "$(ps -p "$pid" -o args= 2>/dev/null || true)" in
      "$installed_executable"*) kill "$pid" >/dev/null 2>&1 || true ;;
    esac
  done

  local deadline=$((SECONDS + 5))
  while ((SECONDS < deadline)); do
    local remaining=0
    (pgrep -x "$APP_NAME" || true) | while IFS= read -r pid; do
      [[ -n "$pid" ]] || continue
      case "$(ps -p "$pid" -o args= 2>/dev/null || true)" in
        "$installed_executable"*) echo "$pid" ;;
      esac
    done | grep -q . && remaining=1 || true
    [[ "$remaining" == 0 ]] && return
    sleep 0.2
  done

  (pgrep -x "$APP_NAME" || true) | while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    case "$(ps -p "$pid" -o args= 2>/dev/null || true)" in
      "$installed_executable"*) kill -9 "$pid" >/dev/null 2>&1 || true ;;
    esac
  done
}

installed_acceptance_process_matches() {
  local pid="$1"
  local installed_executable="$2"
  local acceptance_root="$3"
  local defaults_suite="$4"
  /usr/bin/swift "$EVIDENCE_HELPER" process \
    "$pid" "$installed_executable" -- \
    --lexiray-acceptance-profile \
    --lexiray-acceptance-workspace-root "$ROOT_DIR" \
    --lexiray-acceptance-root "$acceptance_root" \
    --lexiray-acceptance-defaults-suite "$defaults_suite" >/dev/null 2>&1
}

find_installed_acceptance_pid() {
  local installed_executable="$1"
  local acceptance_root="$2"
  local defaults_suite="$3"
  local pid
  (pgrep -x "$APP_NAME" || true) | while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    if installed_acceptance_process_matches \
      "$pid" "$installed_executable" "$acceptance_root" "$defaults_suite"; then
      printf '%s\n' "$pid"
      break
    fi
  done
}

register_app() {
  /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister \
    -f -R -trusted "$1" >/dev/null
}

install_destination_is_replaceable() {
  local destination="$1"
  if [[ ! -e "$destination" && ! -L "$destination" ]]; then
    return 0
  fi
  [[ -d "$destination" && ! -L "$destination" ]]
}

atomic_replace() {
  /usr/bin/swift "$ROOT_DIR/script/atomic_replace.swift" "$@"
}

atomic_rename_file() {
  /usr/bin/swift "$ROOT_DIR/script/atomic_rename.swift" "$1" "$2"
}

bundle_cdhash() {
  [[ -d "$1" ]] || return 0
  { /usr/bin/codesign -dvvv "$1"; } 2>&1 | awk -F= '
    /^CDHash=/ && !found {
      print $2
      found = 1
    }
  '
}

bundle_executable_sha256() {
  local app="$1"
  local executable
  [[ -d "$app" && ! -L "$app" ]] || return 0
  executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Contents/Info.plist" 2>/dev/null || true)"
  [[ -n "$executable" && -f "$app/Contents/MacOS/$executable" ]] || return 0
  /usr/bin/shasum -a 256 "$app/Contents/MacOS/$executable" | /usr/bin/awk '{print $1}'
}

bundle_certificate_sha256() {
  lexiray_app_certificate_sha256 "$1"
}

bundle_requirement_sha256() {
  lexiray_app_designated_requirement_sha256 "$1"
}

bundle_entitlements_sha256() {
  lexiray_app_entitlements_sha256 "$1"
}

bundle_root_device() {
  [[ -d "$1" && ! -L "$1" ]] || return 1
  /usr/bin/stat -f '%d' "$1"
}

bundle_root_inode() {
  [[ -d "$1" && ! -L "$1" ]] || return 1
  /usr/bin/stat -f '%i' "$1"
}

bundle_matches_object() {
  [[ "$2" =~ ^[0-9]+$ && "$3" =~ ^[0-9]+$ && -d "$1" && ! -L "$1" &&
    "$(bundle_root_device "$1")" == "$2" && "$(bundle_root_inode "$1")" == "$3" ]]
}

identity_values_valid() {
  [[ "$1" =~ ^[0-9a-fA-F]{40}$ &&
    "$2" =~ ^[0-9a-fA-F]{64}$ &&
    "$3" =~ ^[0-9a-fA-F]{64}$ &&
    "$4" =~ ^[0-9a-fA-F]{64}$ &&
    "$5" =~ ^[0-9a-fA-F]{64}$ ]]
}

bundle_matches_identity() {
  local app="$1"
  local expected_cdhash="$2"
  local expected_executable="$3"
  local expected_certificate="$4"
  local expected_requirement="$5"
  local expected_entitlements="$6"
  local expected_device="${7:-}"
  local expected_inode="${8:-}"
  [[ -d "$app" && ! -L "$app" ]] || return 1
  identity_values_valid \
    "$expected_cdhash" "$expected_executable" "$expected_certificate" \
    "$expected_requirement" "$expected_entitlements" || return 1
  if [[ -n "$expected_device" || -n "$expected_inode" ]]; then
    bundle_matches_object "$app" "$expected_device" "$expected_inode" || return 1
  fi
  /usr/bin/codesign --verify --deep --strict "$app" >/dev/null 2>&1 || return 1
  [[ "$(bundle_cdhash "$app")" == "$expected_cdhash" &&
    "$(bundle_executable_sha256 "$app")" == "$expected_executable" &&
    "$(bundle_certificate_sha256 "$app" 2>/dev/null || true)" == "$expected_certificate" &&
    "$(bundle_requirement_sha256 "$app" 2>/dev/null || true)" == "$expected_requirement" &&
    "$(bundle_entitlements_sha256 "$app" 2>/dev/null || true)" == "$expected_entitlements" ]]
}

new_transaction_id() {
  /usr/bin/uuidgen | /usr/bin/tr '[:upper:]' '[:lower:]'
}

valid_transaction_id() {
  [[ "$1" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$ ]]
}

installed_acceptance_root_path() {
  local workspace="$1"
  local fingerprint="$2"
  local transaction_id="$3"
  [[ "$fingerprint" =~ ^[0-9a-f]{64}$ ]] || return 1
  valid_transaction_id "$transaction_id" || return 1
  printf '%s/build/acceptance-data/installed-%s-%s\n' \
    "$workspace" "$fingerprint" "$transaction_id"
}

installed_acceptance_defaults_suite() {
  local fingerprint="$1"
  local transaction_id="$2"
  [[ "$fingerprint" =~ ^[0-9a-f]{64}$ ]] || return 1
  valid_transaction_id "$transaction_id" || return 1
  printf 'io.github.tensornull.lexiray.acceptance.installed.%s.%s\n' \
    "${fingerprint:0:16}" "${transaction_id//-/}"
}

ensure_canonical_acceptance_directory() {
  local path="$1"
  if [[ ! -e "$path" && ! -L "$path" ]]; then
    /bin/mkdir -m 700 -- "$path" || die "could not create acceptance directory: $path"
  fi
  [[ -d "$path" && ! -L "$path" && "$(/bin/realpath "$path")" == "$path" ]] ||
    die "acceptance directory must be a canonical non-symlink directory: $path"
}

create_installed_acceptance_root() {
  local workspace="$1"
  local fingerprint="$2"
  local transaction_id="$3"
  local build_root="$workspace/build"
  local acceptance_base="$build_root/acceptance-data"

  [[ "$workspace" == /* && -d "$workspace" && ! -L "$workspace" &&
    "$(/bin/realpath "$workspace")" == "$workspace" ]] ||
    die "acceptance workspace must be a canonical non-symlink directory"
  ensure_canonical_acceptance_directory "$build_root"
  ensure_canonical_acceptance_directory "$acceptance_base"
  ACCEPTANCE_ROOT="$(installed_acceptance_root_path \
    "$workspace" "$fingerprint" "$transaction_id")" ||
    die "could not derive a transaction-owned acceptance root"
  [[ ! -e "$ACCEPTANCE_ROOT" && ! -L "$ACCEPTANCE_ROOT" ]] ||
    die "transaction-owned acceptance root already exists: $ACCEPTANCE_ROOT"
  /bin/mkdir -m 700 -- "$ACCEPTANCE_ROOT" ||
    die "could not exclusively create acceptance root: $ACCEPTANCE_ROOT"
  ACCEPTANCE_ROOT_DEVICE="$(bundle_root_device "$ACCEPTANCE_ROOT")"
  ACCEPTANCE_ROOT_INODE="$(bundle_root_inode "$ACCEPTANCE_ROOT")"
  bundle_matches_object \
    "$ACCEPTANCE_ROOT" "$ACCEPTANCE_ROOT_DEVICE" "$ACCEPTANCE_ROOT_INODE" ||
    die "acceptance root identity could not be captured"
}

acquire_install_lock() {
  if [[ "$INSTALL_LIBRARY_ONLY" == 1 ]]; then
    mkdir -p "$(dirname "$LOCK_FILE")"
    exec 9>"$LOCK_FILE"
    /usr/bin/lockf -s -t 0 9 || die "another LexiRay installation is active"
  else
    [[ "${LEXIRAY_INSTALL_LOCK_HELD:-}" == 1 && -e /dev/fd/9 &&
      "$LOCK_FILE" == /Applications/.io.github.tensornull.lexiray.install.lock ]] ||
      die "production installation requires the secure machine-wide lock launcher"
    /usr/bin/swift "$ROOT_DIR/script/install_lock_validate.swift" "$LOCK_FILE" 9 ||
      die "inherited machine-wide install lock could not be validated"
  fi
  LOCK_HELD=1
}

release_install_lock() {
  if [[ "$LOCK_HELD" == 1 ]]; then
    exec 9>&-
    LOCK_HELD=0
  fi
}

validate_transaction_target() {
  local parent
  parent="$(dirname "$TRANSACTION_FILE")"
  [[ "$TRANSACTION_FILE" == /* && "$parent" == "$(dirname "$APP_DST")" &&
    "$parent" != *'//'* && "$parent" != *'/./'* && "$parent" != *'/../'* &&
    -d "$parent" && ! -L "$parent" && "$(/bin/realpath "$parent")" == "$parent" ]] ||
    die "install transaction parent must be the canonical app destination directory"
  [[ ! -L "$TRANSACTION_FILE" && ! -d "$TRANSACTION_FILE" ]] ||
    die "install transaction marker must be absent or a regular non-symlink file"
  [[ ! -e "$TRANSACTION_FILE" || -f "$TRANSACTION_FILE" ]] ||
    die "install transaction marker has an unsupported file type"
}

write_transaction() {
  local state="$1"
  local had_previous="$2"
  local candidate_cdhash="$3"
  local candidate_executable="$4"
  local candidate_certificate="$5"
  local candidate_requirement="$6"
  local candidate_entitlements="$7"
  local candidate_device="$8"
  local candidate_inode="$9"
  local previous_cdhash="${10}"
  local previous_executable="${11}"
  local previous_certificate="${12}"
  local previous_requirement="${13}"
  local previous_entitlements="${14}"
  local previous_device="${15}"
  local previous_inode="${16}"
  local tmp
  [[ "$TRANSACTION_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$ ]] ||
    die "invalid install transaction id"
  [[ "$STAGING" == "$APP_DST.agent-installing-$TRANSACTION_ID" ]] || die "invalid install staging path"
  identity_values_valid \
    "$candidate_cdhash" "$candidate_executable" "$candidate_certificate" \
    "$candidate_requirement" "$candidate_entitlements" || die "invalid candidate transaction identity"
  [[ "$candidate_device" =~ ^[0-9]+$ && "$candidate_inode" =~ ^[0-9]+$ ]] ||
    die "invalid candidate transaction object identity"
  if [[ "$had_previous" == true ]]; then
    identity_values_valid \
      "$previous_cdhash" "$previous_executable" "$previous_certificate" \
      "$previous_requirement" "$previous_entitlements" || die "invalid previous transaction identity"
    [[ "$previous_device" =~ ^[0-9]+$ && "$previous_inode" =~ ^[0-9]+$ ]] ||
      die "invalid previous transaction object identity"
  elif [[ "$had_previous" != false || -n "$previous_cdhash$previous_executable$previous_certificate$previous_requirement$previous_entitlements$previous_device$previous_inode" ]]; then
    die "invalid first-install previous identity"
  fi
  validate_transaction_target
  tmp="$(mktemp "$(dirname "$TRANSACTION_FILE")/.install-transaction.XXXXXX")"
  /usr/bin/plutil -create xml1 "$tmp"
  /usr/bin/plutil -insert schema_version -integer 3 -- "$tmp"
  /usr/bin/plutil -insert transaction_id -string "$TRANSACTION_ID" -- "$tmp"
  /usr/bin/plutil -insert state -string "$state" -- "$tmp"
  /usr/bin/plutil -insert had_previous -bool "$had_previous" -- "$tmp"
  /usr/bin/plutil -insert staging -string "$STAGING" -- "$tmp"
  /usr/bin/plutil -insert destination -string "$APP_DST" -- "$tmp"
  /usr/bin/plutil -insert candidate_cdhash -string "$candidate_cdhash" -- "$tmp"
  /usr/bin/plutil -insert candidate_executable_sha256 -string "$candidate_executable" -- "$tmp"
  /usr/bin/plutil -insert candidate_certificate_sha256 -string "$candidate_certificate" -- "$tmp"
  /usr/bin/plutil -insert candidate_designated_requirement_sha256 -string "$candidate_requirement" -- "$tmp"
  /usr/bin/plutil -insert candidate_entitlements_sha256 -string "$candidate_entitlements" -- "$tmp"
  /usr/bin/plutil -insert candidate_root_device -string "$candidate_device" -- "$tmp"
  /usr/bin/plutil -insert candidate_root_inode -string "$candidate_inode" -- "$tmp"
  /usr/bin/plutil -insert previous_cdhash -string "$previous_cdhash" -- "$tmp"
  /usr/bin/plutil -insert previous_executable_sha256 -string "$previous_executable" -- "$tmp"
  /usr/bin/plutil -insert previous_certificate_sha256 -string "$previous_certificate" -- "$tmp"
  /usr/bin/plutil -insert previous_designated_requirement_sha256 -string "$previous_requirement" -- "$tmp"
  /usr/bin/plutil -insert previous_entitlements_sha256 -string "$previous_entitlements" -- "$tmp"
  /usr/bin/plutil -insert previous_root_device -string "$previous_device" -- "$tmp"
  /usr/bin/plutil -insert previous_root_inode -string "$previous_inode" -- "$tmp"
  chmod 644 "$tmp"
  if ! atomic_rename_file "$tmp" "$TRANSACTION_FILE"; then
    rm -f -- "$tmp"
    die "could not atomically persist the install transaction"
  fi
}

set_transaction_state() {
  local tmp
  validate_transaction_target
  [[ -f "$TRANSACTION_FILE" && ! -L "$TRANSACTION_FILE" ]] ||
    die "install transaction marker is unavailable"
  tmp="$(mktemp "$(dirname "$TRANSACTION_FILE")/.install-transaction-state.XXXXXX")"
  /usr/bin/plutil -convert xml1 -o "$tmp" -- "$TRANSACTION_FILE"
  /usr/bin/plutil -replace state -string "$1" -- "$tmp"
  chmod 644 "$tmp"
  if ! atomic_rename_file "$tmp" "$TRANSACTION_FILE"; then
    rm -f -- "$tmp"
    die "could not atomically update the install transaction state"
  fi
}

installed_transaction_valid() {
  local transaction_id="$1"
  local app="$2"
  [[ -x "$RECEIPT_TOOL" ]] || return 1
  "$RECEIPT_TOOL" installed-transaction-valid "$transaction_id" "$app" >/dev/null 2>&1
}

recovery_error() {
  echo "INSTALL_RECOVERY_ERROR: $*; transaction artifacts were preserved" >&2
  return 1
}

recover_interrupted_install() {
  if [[ ! -e "$TRANSACTION_FILE" && ! -L "$TRANSACTION_FILE" ]]; then
    return
  fi
  [[ -f "$TRANSACTION_FILE" && ! -L "$TRANSACTION_FILE" ]] || {
    recovery_error "install transaction marker is not a regular non-symlink file"
    return 1
  }
  local schema transaction_id state had_previous staging destination
  local candidate_cdhash candidate_executable candidate_certificate candidate_requirement candidate_entitlements
  local candidate_device candidate_inode
  local previous_cdhash previous_executable previous_certificate previous_requirement previous_entitlements
  local previous_device previous_inode
  schema="$(/usr/libexec/PlistBuddy -c 'Print :schema_version' "$TRANSACTION_FILE" 2>/dev/null || true)"
  transaction_id="$(/usr/libexec/PlistBuddy -c 'Print :transaction_id' "$TRANSACTION_FILE" 2>/dev/null || true)"
  state="$(/usr/libexec/PlistBuddy -c 'Print :state' "$TRANSACTION_FILE" 2>/dev/null || true)"
  had_previous="$(/usr/libexec/PlistBuddy -c 'Print :had_previous' "$TRANSACTION_FILE" 2>/dev/null || true)"
  staging="$(/usr/libexec/PlistBuddy -c 'Print :staging' "$TRANSACTION_FILE" 2>/dev/null || true)"
  destination="$(/usr/libexec/PlistBuddy -c 'Print :destination' "$TRANSACTION_FILE" 2>/dev/null || true)"
  candidate_cdhash="$(/usr/libexec/PlistBuddy -c 'Print :candidate_cdhash' "$TRANSACTION_FILE" 2>/dev/null || true)"
  candidate_executable="$(/usr/libexec/PlistBuddy -c 'Print :candidate_executable_sha256' "$TRANSACTION_FILE" 2>/dev/null || true)"
  candidate_certificate="$(/usr/libexec/PlistBuddy -c 'Print :candidate_certificate_sha256' "$TRANSACTION_FILE" 2>/dev/null || true)"
  candidate_requirement="$(/usr/libexec/PlistBuddy -c 'Print :candidate_designated_requirement_sha256' "$TRANSACTION_FILE" 2>/dev/null || true)"
  candidate_entitlements="$(/usr/libexec/PlistBuddy -c 'Print :candidate_entitlements_sha256' "$TRANSACTION_FILE" 2>/dev/null || true)"
  candidate_device="$(/usr/libexec/PlistBuddy -c 'Print :candidate_root_device' "$TRANSACTION_FILE" 2>/dev/null || true)"
  candidate_inode="$(/usr/libexec/PlistBuddy -c 'Print :candidate_root_inode' "$TRANSACTION_FILE" 2>/dev/null || true)"
  previous_cdhash="$(/usr/libexec/PlistBuddy -c 'Print :previous_cdhash' "$TRANSACTION_FILE" 2>/dev/null || true)"
  previous_executable="$(/usr/libexec/PlistBuddy -c 'Print :previous_executable_sha256' "$TRANSACTION_FILE" 2>/dev/null || true)"
  previous_certificate="$(/usr/libexec/PlistBuddy -c 'Print :previous_certificate_sha256' "$TRANSACTION_FILE" 2>/dev/null || true)"
  previous_requirement="$(/usr/libexec/PlistBuddy -c 'Print :previous_designated_requirement_sha256' "$TRANSACTION_FILE" 2>/dev/null || true)"
  previous_entitlements="$(/usr/libexec/PlistBuddy -c 'Print :previous_entitlements_sha256' "$TRANSACTION_FILE" 2>/dev/null || true)"
  previous_device="$(/usr/libexec/PlistBuddy -c 'Print :previous_root_device' "$TRANSACTION_FILE" 2>/dev/null || true)"
  previous_inode="$(/usr/libexec/PlistBuddy -c 'Print :previous_root_inode' "$TRANSACTION_FILE" 2>/dev/null || true)"

  if [[ "$schema" != 3 ||
    ! "$transaction_id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$ ||
    "$destination" != "$APP_DST" || "$staging" != "$APP_DST.agent-installing-$transaction_id" ||
    ! "$state" =~ ^(prepared|validated|rolling_back|rollback_cleanup|commit_cleanup)$ ]] ||
    ! identity_values_valid \
      "$candidate_cdhash" "$candidate_executable" "$candidate_certificate" \
      "$candidate_requirement" "$candidate_entitlements" ||
    [[ ! "$candidate_device" =~ ^[0-9]+$ || ! "$candidate_inode" =~ ^[0-9]+$ ]]; then
    recovery_error "refusing malformed install transaction: $TRANSACTION_FILE"
    return 1
  fi
  if [[ "$had_previous" == true ]]; then
    identity_values_valid \
      "$previous_cdhash" "$previous_executable" "$previous_certificate" \
      "$previous_requirement" "$previous_entitlements" ||
      {
        recovery_error "previous app identity is missing"
        return 1
      }
    [[ "$previous_device" =~ ^[0-9]+$ && "$previous_inode" =~ ^[0-9]+$ ]] || {
      recovery_error "previous app root object identity is missing"
      return 1
    }
  elif [[ "$had_previous" != false || -n "$previous_cdhash" || -n "$previous_executable" ||
    -n "$previous_certificate" || -n "$previous_requirement" || -n "$previous_entitlements" ||
    -n "$previous_device" || -n "$previous_inode" ]]; then
    recovery_error "first-install transaction has an invalid previous identity"
    return 1
  fi

  if [[ "$state" == prepared ]]; then
    set_transaction_state rolling_back
    state=rolling_back
  elif [[ "$state" == validated ]]; then
    local swap_state_valid=0
    if [[ "$had_previous" == true ]] && bundle_matches_identity \
      "$staging" "$previous_cdhash" "$previous_executable" "$previous_certificate" \
      "$previous_requirement" "$previous_entitlements" "$previous_device" "$previous_inode"; then
      swap_state_valid=1
    elif [[ "$had_previous" == false && ! -e "$staging" ]]; then
      swap_state_valid=1
    fi
    if [[ "$swap_state_valid" == 1 ]] && bundle_matches_identity \
      "$destination" "$candidate_cdhash" "$candidate_executable" "$candidate_certificate" \
      "$candidate_requirement" "$candidate_entitlements" "$candidate_device" "$candidate_inode" &&
      installed_transaction_valid "$transaction_id" "$destination"; then
      set_transaction_state commit_cleanup
      state=commit_cleanup
    else
      set_transaction_state rolling_back
      state=rolling_back
    fi
  fi

  if [[ "$state" == rolling_back ]]; then
    if [[ "$had_previous" == true ]]; then
      if bundle_matches_identity \
        "$destination" "$previous_cdhash" "$previous_executable" "$previous_certificate" \
        "$previous_requirement" "$previous_entitlements" "$previous_device" "$previous_inode"; then
        set_transaction_state rollback_cleanup
        state=rollback_cleanup
      elif bundle_matches_identity \
        "$destination" "$candidate_cdhash" "$candidate_executable" "$candidate_certificate" \
        "$candidate_requirement" "$candidate_entitlements" "$candidate_device" "$candidate_inode" &&
        bundle_matches_identity \
          "$staging" "$previous_cdhash" "$previous_executable" "$previous_certificate" \
          "$previous_requirement" "$previous_entitlements" "$previous_device" "$previous_inode"; then
        stop_lexiray_apps || true
        atomic_replace \
          "$staging" "$destination" existing "$candidate_device" "$candidate_inode" || {
          recovery_error "could not restore the previous app"
          return 1
        }
        bundle_matches_identity \
          "$destination" "$previous_cdhash" "$previous_executable" "$previous_certificate" \
          "$previous_requirement" "$previous_entitlements" "$previous_device" "$previous_inode" ||
          {
            recovery_error "restored destination identity is inconsistent"
            return 1
          }
        set_transaction_state rollback_cleanup
        state=rollback_cleanup
        register_app "$destination" || true
      else
        recovery_error "interrupted install state is ambiguous"
        return 1
      fi
    else
      if [[ ! -e "$destination" && ! -L "$destination" ]] && bundle_matches_identity \
        "$staging" "$candidate_cdhash" "$candidate_executable" "$candidate_certificate" \
        "$candidate_requirement" "$candidate_entitlements" "$candidate_device" "$candidate_inode"; then
        set_transaction_state rollback_cleanup
        state=rollback_cleanup
      elif [[ ! -e "$staging" && ! -L "$staging" ]] && bundle_matches_identity \
        "$destination" "$candidate_cdhash" "$candidate_executable" "$candidate_certificate" \
        "$candidate_requirement" "$candidate_entitlements" "$candidate_device" "$candidate_inode"; then
        stop_lexiray_apps || true
        atomic_replace "$destination" "$staging" absent || {
          recovery_error "could not quarantine the first-install candidate"
          return 1
        }
        [[ ! -e "$destination" && ! -L "$destination" ]] && bundle_matches_identity \
          "$staging" "$candidate_cdhash" "$candidate_executable" "$candidate_certificate" \
          "$candidate_requirement" "$candidate_entitlements" "$candidate_device" "$candidate_inode" || {
          recovery_error "quarantined first-install candidate identity is inconsistent"
          return 1
        }
        set_transaction_state rollback_cleanup
        state=rollback_cleanup
      else
        recovery_error "interrupted first-install state is ambiguous"
        return 1
      fi
    fi
  fi

  if [[ "$state" == rollback_cleanup ]]; then
    if [[ "$had_previous" == true ]]; then
      bundle_matches_identity \
        "$destination" "$previous_cdhash" "$previous_executable" "$previous_certificate" \
        "$previous_requirement" "$previous_entitlements" "$previous_device" "$previous_inode" ||
        {
          recovery_error "rollback destination no longer matches the previous app"
          return 1
        }
      if [[ -e "$staging" || -L "$staging" ]]; then
        bundle_matches_object "$staging" "$candidate_device" "$candidate_inode" || {
          recovery_error "rollback cleanup staging object was replaced"
          return 1
        }
        rm -rf -- "$staging"
      fi
      register_app "$destination" || true
      echo "INSTALL_RECOVERY: restored the verified previous app"
    else
      [[ ! -e "$destination" && ! -L "$destination" ]] || {
        recovery_error "first-install rollback found an unknown destination"
        return 1
      }
      if [[ -e "$staging" || -L "$staging" ]]; then
        bundle_matches_object "$staging" "$candidate_device" "$candidate_inode" || {
          recovery_error "first-install cleanup staging object was replaced"
          return 1
        }
        rm -rf -- "$staging"
      fi
      echo "INSTALL_RECOVERY: rolled back the interrupted first installation"
    fi
    rm -f -- "$TRANSACTION_FILE"
    return
  fi

  if [[ "$state" == commit_cleanup ]]; then
    bundle_matches_identity \
      "$destination" "$candidate_cdhash" "$candidate_executable" "$candidate_certificate" \
      "$candidate_requirement" "$candidate_entitlements" "$candidate_device" "$candidate_inode" ||
      {
        recovery_error "committed destination no longer matches the candidate"
        return 1
      }
    if [[ -e "$staging" || -L "$staging" ]]; then
      if [[ "$had_previous" == true ]]; then
        bundle_matches_object "$staging" "$previous_device" "$previous_inode" || {
          recovery_error "commit cleanup staging object was replaced"
          return 1
        }
      else
        recovery_error "committed first installation has an unexpected staging object"
        return 1
      fi
      rm -rf -- "$staging"
    fi
    rm -f -- "$TRANSACTION_FILE"
    echo "INSTALL_RECOVERY: retained the receipt-verified committed installation"
    return
  fi

  recovery_error "install transaction reached an unknown state"
  return 1
}

rollback() {
  local status=$?
  trap - EXIT HUP INT TERM
  if [[ -e "$TRANSACTION_FILE" || -L "$TRANSACTION_FILE" ]]; then
    if recover_interrupted_install; then
      SWAP_POSSIBLE=0
    else
      status=1
    fi
  elif [[ "$SWAP_POSSIBLE" == 1 ]]; then
    echo "INSTALL_RECOVERY_ERROR: transaction marker disappeared after swap became possible; preserving all app objects" >&2
    status=1
  elif [[ ! -f "$TRANSACTION_FILE" && -n "$STAGING" && -d "$STAGING" ]]; then
    if bundle_matches_object "$STAGING" "$STAGING_DEVICE" "$STAGING_INODE"; then
      rm -rf -- "$STAGING"
    else
      echo "INSTALL_RECOVERY_ERROR: unowned staging object was preserved: $STAGING" >&2
      status=1
    fi
  fi
  release_install_lock
  exit "$status"
}

if [[ "$INSTALL_LIBRARY_ONLY" == 1 ]]; then
  return 0 2>/dev/null || exit 0
fi
if [[ "${LEXIRAY_INSTALL_LOCK_HELD:-}" != 1 ]]; then
  exec /usr/bin/swift "$ROOT_DIR/script/install_lock.swift" \
    "$LOCK_FILE" "$ROOT_DIR/script/install_applications.sh" "$@"
fi
trap rollback EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

cd "$ROOT_DIR"
acquire_install_lock
recover_interrupted_install
[[ -x "$RECEIPT_TOOL" ]] || die "acceptance receipt helper is missing"
receipt="$($RECEIPT_TOOL require-candidate)" || die "current source has no valid candidate receipt"
candidate="$($RECEIPT_TOOL field app.path)"
fingerprint="$($RECEIPT_TOOL field source_fingerprint)"
expected_cdhash="$($RECEIPT_TOOL field app.cdhash)"
expected_executable="$($RECEIPT_TOOL field app.executable_sha256)"
expected_certificate="$($RECEIPT_TOOL field app.certificate_sha256)"
expected_requirement="$($RECEIPT_TOOL field app.designated_requirement_sha256)"
expected_entitlements="$($RECEIPT_TOOL field app.entitlements_sha256)"
identity_values_valid \
  "$expected_cdhash" "$expected_executable" "$expected_certificate" \
  "$expected_requirement" "$expected_entitlements" || die "candidate signing identity is incomplete"
[[ -d "$candidate" ]] || die "candidate app is missing: $candidate"

active_builds="$(running_builds)"
[[ -z "$active_builds" ]] || {
  echo "$active_builds" >&2
  die "a build or verification process is still running"
}

TRANSACTION_ID="$(new_transaction_id)"
STAGING="$APP_DST.agent-installing-$TRANSACTION_ID"
[[ ! -e "$STAGING" && ! -L "$STAGING" ]] ||
  die "transaction staging path already exists: $STAGING"
/bin/mkdir -m 700 -- "$STAGING" || die "could not exclusively create install staging"
STAGING_DEVICE="$(bundle_root_device "$STAGING")"
STAGING_INODE="$(bundle_root_inode "$STAGING")"
/usr/bin/ditto "$candidate" "$STAGING"
/usr/bin/codesign --verify --deep --strict "$STAGING" || die "staged app signature is invalid"
$RECEIPT_TOOL verify-app-match "$STAGING" >/dev/null || die "staged app does not match the accepted candidate"
candidate_device="$(bundle_root_device "$STAGING")"
candidate_inode="$(bundle_root_inode "$STAGING")"
[[ "$candidate_device" =~ ^[0-9]+$ && "$candidate_inode" =~ ^[0-9]+$ ]] ||
  die "candidate root object identity could not be captured"
[[ "$candidate_device" == "$STAGING_DEVICE" && "$candidate_inode" == "$STAGING_INODE" ]] ||
  die "staged app root was replaced while copying the candidate"

stop_lexiray_apps
install_destination_is_replaceable "$APP_DST" ||
  die "install destination must be absent or a non-symlink app directory: $APP_DST"
had_previous=false
[[ -d "$APP_DST" ]] && had_previous=true
previous_cdhash=""
previous_executable=""
previous_certificate=""
previous_requirement=""
previous_entitlements=""
previous_device=""
previous_inode=""
if [[ "$had_previous" == true ]]; then
  previous_cdhash="$(bundle_cdhash "$APP_DST")"
  previous_executable="$(bundle_executable_sha256 "$APP_DST")"
  previous_certificate="$(bundle_certificate_sha256 "$APP_DST" 2>/dev/null || true)"
  previous_requirement="$(bundle_requirement_sha256 "$APP_DST" 2>/dev/null || true)"
  previous_entitlements="$(bundle_entitlements_sha256 "$APP_DST" 2>/dev/null || true)"
  previous_device="$(bundle_root_device "$APP_DST" 2>/dev/null || true)"
  previous_inode="$(bundle_root_inode "$APP_DST" 2>/dev/null || true)"
  bundle_matches_identity \
    "$APP_DST" "$previous_cdhash" "$previous_executable" "$previous_certificate" \
    "$previous_requirement" "$previous_entitlements" "$previous_device" "$previous_inode" ||
    die "existing app has no valid recoverable signing identity"
fi
write_transaction prepared "$had_previous" \
  "$expected_cdhash" "$expected_executable" "$expected_certificate" \
  "$expected_requirement" "$expected_entitlements" "$candidate_device" "$candidate_inode" \
  "$previous_cdhash" "$previous_executable" "$previous_certificate" \
  "$previous_requirement" "$previous_entitlements" "$previous_device" "$previous_inode"
SWAP_POSSIBLE=1
if [[ "$had_previous" == true ]]; then
  atomic_replace \
    "$STAGING" "$APP_DST" existing "$previous_device" "$previous_inode"
else
  atomic_replace "$STAGING" "$APP_DST" absent
fi
register_app "$APP_DST"
/usr/bin/codesign --verify --deep --strict "$APP_DST" || die "installed app signature is invalid"
$RECEIPT_TOOL verify-app-match "$APP_DST" >/dev/null || die "installed app does not match the accepted candidate"

create_installed_acceptance_root "$ROOT_DIR" "$fingerprint" "$TRANSACTION_ID"
acceptance_root="$ACCEPTANCE_ROOT"
defaults_suite="$(installed_acceptance_defaults_suite "$fingerprint" "$TRANSACTION_ID")" ||
  die "could not derive a transaction-owned defaults suite"
printf '%s\n' 'LexiRay acceptance root v1' >"$acceptance_root/.lexiray-acceptance-root"
cp "$ROOT_DIR/script/ui/fixtures/computer-use-providers.json" "$acceptance_root/providers.json"
cp "$ROOT_DIR/script/ui/fixtures/history.json" "$acceptance_root/history.json"
chmod 600 \
  "$acceptance_root/.lexiray-acceptance-root" \
  "$acceptance_root/providers.json" \
  "$acceptance_root/history.json"
bundle_matches_object \
  "$acceptance_root" "$ACCEPTANCE_ROOT_DEVICE" "$ACCEPTANCE_ROOT_INODE" ||
  die "acceptance root was replaced while writing fixtures"

/usr/bin/open -n "$APP_DST" --args \
  --lexiray-acceptance-profile \
  --lexiray-acceptance-workspace-root "$ROOT_DIR" \
  --lexiray-acceptance-root "$acceptance_root" \
  --lexiray-acceptance-defaults-suite "$defaults_suite"

installed_executable="$APP_DST/Contents/MacOS/$APP_NAME"
running_pid=""
deadline=$((SECONDS + 10))
while ((SECONDS < deadline)); do
  running_pid="$(find_installed_acceptance_pid \
    "$installed_executable" "$acceptance_root" "$defaults_suite")"
  [[ -n "$running_pid" ]] && break
  sleep 0.2
done
[[ -n "$running_pid" ]] || die "installed app did not launch with the acceptance profile"

$RECEIPT_TOOL verify-app-match "$APP_DST" >/dev/null || die "installed app became stale before acceptance launch"
set_transaction_state validated
$RECEIPT_TOOL mark-installed "$APP_DST" "$running_pid" "$TRANSACTION_ID" >/dev/null ||
  die "installed app does not match the accepted candidate"
$RECEIPT_TOOL installed-transaction-valid "$TRANSACTION_ID" "$APP_DST" >/dev/null ||
  die "installed receipt transaction could not be revalidated"
recover_interrupted_install || die "committed installation could not be reconciled"
SWAP_POSSIBLE=0
trap - EXIT HUP INT TERM
release_install_lock

signature="$({ /usr/bin/codesign -dvvv "$APP_DST"; } 2>&1)"
authority="$(awk -F= '/^Authority=/{print substr($0, index($0, "=") + 1); exit}' <<<"$signature")"
cdhash="$(awk -F= '/^CDHash=/{print $2; exit}' <<<"$signature")"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DST/Contents/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_DST/Contents/Info.plist")"

echo "INSTALLED=$APP_DST"
echo "VERSION=$version"
echo "BUILD=$build"
echo "AUTHORITY=$authority"
echo "CDHASH=$cdhash"
echo "RUNNING_PID=$running_pid"
echo "RUNNING_PATH=$installed_executable"
echo "ACCEPTANCE_ROOT=$acceptance_root"
echo "ACCEPTANCE_DEFAULTS_SUITE=$defaults_suite"
echo "RECEIPT=$receipt"

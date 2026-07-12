#!/usr/bin/env bash

lexiray_capability_plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null
}

lexiray_release_state_value() {
  /usr/bin/awk -F= -v wanted="$2" '
    $1 == wanted { sub(/^[^=]*=/, "", $0); value = $0 }
    END { if (value != "") print value; else exit 1 }
  ' "$1"
}

lexiray_release_ancestor_valid() {
  local root_dir="$1"
  local orchestrator_pid="$2"
  local version="$3"
  local current_pid="${PPID:-0}"
  local parent_pid command
  local depth=0

  while [[ "$current_pid" =~ ^[0-9]+$ && "$current_pid" -gt 1 && "$depth" -lt 6 ]]; do
    if [[ "$current_pid" == "$orchestrator_pid" ]]; then
      command="$(ps -ww -p "$current_pid" -o args= 2>/dev/null || true)"
      [[ "$command" == *"script/release.sh"* && "$command" == *" $version"* ]] && return 0
      return 1
    fi
    parent_pid="$(ps -p "$current_pid" -o ppid= 2>/dev/null | /usr/bin/tr -d ' ' || true)"
    current_pid="$parent_pid"
    depth=$((depth + 1))
  done
  return 1
}

lexiray_require_release_capability() {
  local root_dir="$1"
  local version="$2"
  shift 2
  local capability="${LEXIRAY_RELEASE_CAPABILITY_PATH:-}"
  local mode source_commit state_file lock_file orchestrator_pid nonce created_epoch now allowed=0
  local expected_state expected_key expected_tag
  local lock_path_id lock_fd_id lock_parent expected_lock

  [[ -n "$capability" && -f "$capability" && ! -L "$capability" ]] || return 1
  case "$capability" in
    "$root_dir"/build/release-state/.release-capability.*) ;;
    *) return 1 ;;
  esac
  [[ "$(/usr/bin/stat -f '%u' "$capability" 2>/dev/null || true)" == "$(id -u)" &&
    "$(/usr/bin/stat -f '%Lp' "$capability" 2>/dev/null || true)" == 600 ]] || return 1
  [[ "$(lexiray_capability_plist_value "$capability" schema_version)" == 1 &&
    "$(lexiray_capability_plist_value "$capability" version)" == "$version" ]] || return 1

  mode="$(lexiray_capability_plist_value "$capability" mode)"
  for expected_mode in "$@"; do
    [[ "$mode" == "$expected_mode" ]] && allowed=1
  done
  [[ "$allowed" == 1 ]] || return 1

  source_commit="$(lexiray_capability_plist_value "$capability" source_commit)"
  state_file="$(lexiray_capability_plist_value "$capability" state_file)"
  lock_file="$(lexiray_capability_plist_value "$capability" lock_file)"
  orchestrator_pid="$(lexiray_capability_plist_value "$capability" orchestrator_pid)"
  nonce="$(lexiray_capability_plist_value "$capability" nonce)"
  created_epoch="$(lexiray_capability_plist_value "$capability" created_epoch)"
  [[ "$source_commit" =~ ^[0-9a-f]{40}$ && "$orchestrator_pid" =~ ^[0-9]+$ &&
    "$nonce" =~ ^[0-9a-f-]{36}$ && "$created_epoch" =~ ^[0-9]+$ ]] || return 1
  now="$(/bin/date +%s)"
  [[ "$created_epoch" -le "$now" && $((now - created_epoch)) -le 21600 ]] || return 1

  expected_state="$root_dir/build/release-state/v$version-$source_commit.state"
  expected_tag="v$version"
  expected_key="$expected_tag-${source_commit:0:12}"
  [[ "$state_file" == "$expected_state" && -f "$state_file" && ! -L "$state_file" ]] || return 1
  lock_path_id="$(/usr/bin/stat -f '%d:%i' "$lock_file" 2>/dev/null || true)"
  lock_fd_id="$(/usr/bin/stat -f '%d:%i' /dev/fd/9 2>/dev/null || true)"
  expected_lock="/private/tmp/io.github.tensornull.lexiray.release.$(/usr/bin/id -u)/lock"
  lock_parent="${lock_file%/*}"
  [[ "$lock_file" == "$expected_lock" &&
    -d "$lock_parent" && ! -L "$lock_parent" &&
    "$(/usr/bin/stat -f '%u' "$lock_parent" 2>/dev/null || true)" == "$(/usr/bin/id -u)" &&
    "$(/usr/bin/stat -f '%Lp' "$lock_parent" 2>/dev/null || true)" == 700 &&
    "$(/bin/realpath "$lock_parent" 2>/dev/null || true)" == "$lock_parent" &&
    -f "$lock_file" && ! -L "$lock_file" && -e /dev/fd/9 &&
    "$(/usr/bin/stat -f '%u' "$lock_file" 2>/dev/null || true)" == "$(/usr/bin/id -u)" &&
    "$(/usr/bin/stat -f '%l' "$lock_file" 2>/dev/null || true)" == 1 &&
    "$(/usr/bin/stat -f '%Lp' "$lock_file" 2>/dev/null || true)" == 600 &&
    "$(/usr/bin/stat -f '%u' /dev/fd/9 2>/dev/null || true)" == "$(/usr/bin/id -u)" &&
    "$(/usr/bin/stat -f '%l' /dev/fd/9 2>/dev/null || true)" == 1 &&
    -n "$lock_path_id" && "$lock_path_id" == "$lock_fd_id" ]] || return 1
  [[ "$(lexiray_release_state_value "$state_file" version)" == "$version" &&
    "$(lexiray_release_state_value "$state_file" tag)" == "$expected_tag" &&
    "$(lexiray_release_state_value "$state_file" source_commit)" == "$source_commit" &&
    "$(lexiray_release_state_value "$state_file" state_key)" == "$expected_key" &&
    "$(lexiray_release_state_value "$state_file" doctor)" == complete ]] || return 1
  lexiray_release_ancestor_valid "$root_dir" "$orchestrator_pid" "$version" || return 1

  LEXIRAY_VALIDATED_RELEASE_MODE="$mode"
  LEXIRAY_VALIDATED_RELEASE_SOURCE_COMMIT="$source_commit"
  LEXIRAY_VALIDATED_RELEASE_STATE_FILE="$state_file"
  export LEXIRAY_VALIDATED_RELEASE_MODE LEXIRAY_VALIDATED_RELEASE_SOURCE_COMMIT
  export LEXIRAY_VALIDATED_RELEASE_STATE_FILE
}

lexiray_require_github_fallback_context() {
  local source_commit="$1"
  [[ "${GITHUB_ACTIONS:-}" == true &&
    "${GITHUB_REPOSITORY:-}" == "tensornull/LexiRay" &&
    "${GITHUB_EVENT_NAME:-}" == workflow_dispatch &&
    "${GITHUB_WORKFLOW_REF:-}" == tensornull/LexiRay/.github/workflows/release-build.yml@refs/heads/main &&
    "${GITHUB_REF:-}" == refs/heads/main &&
    "${GITHUB_SHA:-}" == "$source_commit" &&
    "$source_commit" =~ ^[0-9a-f]{40}$ ]]
}

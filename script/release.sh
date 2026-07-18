#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=release_identity.sh
source "$ROOT_DIR/script/release_identity.sh"
INFO_PLIST="$ROOT_DIR/LexiRay/Resources/Info.plist"
RELEASE_TEST_MODE="${LEXIRAY_RELEASE_TEST_MODE:-0}"
STATE_DIR="$ROOT_DIR/build/release-state"
GLOBAL_LOCK_FILE="/private/tmp/io.github.tensornull.lexiray.release.$(/usr/bin/id -u)/lock"
if [[ "$RELEASE_TEST_MODE" == 1 ]]; then
  STATE_DIR="${LEXIRAY_RELEASE_STATE_DIR:-$STATE_DIR}"
  GLOBAL_LOCK_FILE="${LEXIRAY_RELEASE_LOCK_FILE:-$GLOBAL_LOCK_FILE}"
fi
REMOTE="origin"
REPOSITORY="$LEXIRAY_RELEASE_REPOSITORY"
WORKFLOW="release-build.yml"
FALLBACK_ARTIFACT_PREFIX="LexiRay-release"
IDENTITY_NAME="$LEXIRAY_RELEASE_IDENTITY_NAME"
STALE_KEYCHAIN="$ROOT_DIR/build/release-signing.keychain-db"
LOCAL_SIGNING_MARKER="$STATE_DIR/local-signing-ready.plist"
DRY_RUN=0
PUBLISH_LOCK=""
PUBLISH_LOCK_HELD=0
RELEASE_CAPABILITY_PATH=""
ASSET_INVALID=1
ASSET_ABSENT=4
ASSET_UNCERTAIN=75

# Release commands must never open an authentication prompt. Missing credentials
# are reported as blockers so an agent can resume after fixing the environment.
export GH_PROMPT_DISABLED=1
export GIT_TERMINAL_PROMPT=0

usage() {
  cat <<'EOF'
usage: script/release.sh <doctor|publish|status> <version-without-v> [--dry-run]

  doctor   Validate the tagged release checkout, acceptance receipt, and release path.
  publish  Publish locally when the fixed identity is accessible; otherwise dispatch
           the GitHub Release Build fallback. A pending fallback exits with status 75.
  status   Inspect or resume a previously dispatched fallback without polling.

Options:
  --dry-run  Perform read-only checks and print the action without packaging,
             uploading, dispatching, downloading assets, or changing release state.
EOF
}

die() {
  echo "release: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is required."
}

validate_version() {
  case "$VERSION" in
    v*) die "Pass the version without a leading v. Example: 0.4.0." ;;
  esac

  if ! lexiray_validate_release_version "$VERSION"; then
    die "Invalid release version: $VERSION"
  fi
}

remote_tag_commit() {
  gh api "repos/$REPOSITORY/commits/$TAG" --jq '.sha' 2>/dev/null
}

state_path_for_commit() {
  local commit="$1"
  printf '%s/%s-%s.state\n' "$STATE_DIR" "$TAG" "$commit"
}

state_get() {
  local key="$1"
  [[ -f "$STATE_FILE" ]] || return 1
  /usr/bin/awk -F= -v wanted="$key" '
    $1 == wanted {
      sub(/^[^=]*=/, "", $0)
      value = $0
    }
    END {
      if (value != "") print value
      else exit 1
    }
  ' "$STATE_FILE"
}

state_set() {
  local key="$1"
  local value="$2"
  local tmp

  [[ "$key" =~ ^[a-z0-9_.-]+$ ]] || die "Invalid release-state key: $key"
  [[ "$value" != *$'\n'* ]] || die "Release-state values cannot contain newlines."
  [[ "$DRY_RUN" -eq 0 ]] || return 0

  mkdir -p "$STATE_DIR"
  tmp="$(/usr/bin/mktemp "$STATE_DIR/.release-state.XXXXXX")"
  if [[ -f "$STATE_FILE" ]]; then
    /usr/bin/awk -F= -v wanted="$key" '$1 != wanted { print }' "$STATE_FILE" >"$tmp"
  fi
  printf '%s=%s\n' "$key" "$value" >>"$tmp"
  /bin/mv -f "$tmp" "$STATE_FILE"
}

state_delete() {
  local key="$1"
  local tmp

  [[ "$key" =~ ^[a-z0-9_.-]+$ ]] || die "Invalid release-state key: $key"
  [[ "$DRY_RUN" -eq 0 && -f "$STATE_FILE" ]] || return 0
  tmp="$(/usr/bin/mktemp "$STATE_DIR/.release-state.XXXXXX")"
  /usr/bin/awk -F= -v wanted="$key" '$1 != wanted { print }' "$STATE_FILE" >"$tmp"
  /bin/mv -f "$tmp" "$STATE_FILE"
}

cleanup_publish_lock() {
  if [[ -n "$RELEASE_CAPABILITY_PATH" ]]; then
    /bin/rm -f -- "$RELEASE_CAPABILITY_PATH"
    RELEASE_CAPABILITY_PATH=""
  fi
  [[ "$PUBLISH_LOCK_HELD" == 1 ]] || return 0
  exec 9>&-
  PUBLISH_LOCK_HELD=0
}

acquire_publish_lock() {
  [[ "$DRY_RUN" -eq 0 ]] || return 0
  [[ "$PUBLISH_LOCK_HELD" == 1 && "${LEXIRAY_RELEASE_LOCK_HELD:-}" == 1 && -e /dev/fd/9 ]] ||
    die "Release command does not hold the secure global release lock."
  if [[ "$RELEASE_TEST_MODE" == 0 ]]; then
    /usr/bin/swift "$ROOT_DIR/script/release_lock_validate.swift" \
      "$GLOBAL_LOCK_FILE" 9 >/dev/null ||
      die "Inherited global release lock is invalid."
  else
    /usr/bin/swift "$ROOT_DIR/script/release_lock_validate.swift" \
      --test "$GLOBAL_LOCK_FILE" 9 >/dev/null ||
      die "Inherited test release lock is invalid."
  fi
}

bootstrap_publish_lock() {
  [[ "$DRY_RUN" -eq 0 ]] || return 0
  if [[ "${LEXIRAY_RELEASE_LOCK_HELD:-}" != 1 || ! -e /dev/fd/9 ]]; then
    if [[ "$RELEASE_TEST_MODE" == 0 ]]; then
      exec /usr/bin/swift "$ROOT_DIR/script/release_lock.swift" \
        "$GLOBAL_LOCK_FILE" "$ROOT_DIR/script/release.sh" "$@"
    else
      exec /usr/bin/swift "$ROOT_DIR/script/release_lock.swift" \
        --test "$GLOBAL_LOCK_FILE" "$ROOT_DIR/script/release.sh" "$@"
    fi
  fi
  PUBLISH_LOCK="$GLOBAL_LOCK_FILE"
  PUBLISH_LOCK_HELD=1
  acquire_publish_lock
  trap cleanup_publish_lock EXIT
}

create_release_capability() {
  local mode="$1"
  local capability nonce
  [[ "$DRY_RUN" -eq 0 && "$PUBLISH_LOCK_HELD" == 1 ]] ||
    die "Release helper capability requires the live global release lock."
  [[ "$STATE_DIR" == "$ROOT_DIR/build/release-state" &&
    "$STATE_FILE" == "$STATE_DIR/$TAG-$SOURCE_COMMIT.state" ]] ||
    die "Release helpers require the canonical release state path."
  [[ -f "$STATE_FILE" && "$(state_get doctor)" == complete ]] ||
    die "Release helper capability requires completed doctor state."

  if [[ -n "$RELEASE_CAPABILITY_PATH" ]]; then
    /bin/rm -f -- "$RELEASE_CAPABILITY_PATH"
  fi
  capability="$(/usr/bin/mktemp "$STATE_DIR/.release-capability.XXXXXX")"
  nonce="$(/usr/bin/uuidgen | /usr/bin/tr '[:upper:]' '[:lower:]')"
  /usr/bin/plutil -create xml1 "$capability"
  /usr/bin/plutil -insert schema_version -integer 1 -- "$capability"
  /usr/bin/plutil -insert mode -string "$mode" -- "$capability"
  /usr/bin/plutil -insert version -string "$VERSION" -- "$capability"
  /usr/bin/plutil -insert source_commit -string "$SOURCE_COMMIT" -- "$capability"
  /usr/bin/plutil -insert state_file -string "$STATE_FILE" -- "$capability"
  /usr/bin/plutil -insert lock_file -string "$GLOBAL_LOCK_FILE" -- "$capability"
  /usr/bin/plutil -insert orchestrator_pid -integer "$$" -- "$capability"
  /usr/bin/plutil -insert nonce -string "$nonce" -- "$capability"
  /usr/bin/plutil -insert created_epoch -integer "$(/bin/date +%s)" -- "$capability"
  /bin/chmod 600 "$capability"
  RELEASE_CAPABILITY_PATH="$capability"
  export LEXIRAY_RELEASE_CAPABILITY_PATH="$capability"
}

initialize_state() {
  STATE_FILE="$(state_path_for_commit "$SOURCE_COMMIT")"
  state_set schema_version 1
  state_set version "$VERSION"
  state_set build "$RELEASE_BUILD"
  state_set certificate_sha256 "$LEXIRAY_RELEASE_CERT_SHA256"
  state_set tag "$TAG"
  state_set source_commit "$SOURCE_COMMIT"
  state_set tag_commit "$TAG_COMMIT"
  state_set source_fingerprint "$SOURCE_FINGERPRINT"
  state_set candidate_certificate_sha256 "$CANDIDATE_CERTIFICATE_SHA256"
  state_set candidate_designated_requirement_sha256 "$CANDIDATE_REQUIREMENT_SHA256"
  state_set candidate_entitlements_sha256 "$CANDIDATE_ENTITLEMENTS_SHA256"
  state_set state_key "$STATE_KEY"
}

list_user_keychains() {
  /usr/bin/security list-keychains -d user 2>/dev/null |
    /usr/bin/sed -E 's/^[[:space:]]*"//; s/"[[:space:]]*$//'
}

cleanup_stale_keychain_search_list() {
  local keychain
  local removed=0
  local -a retained=()

  while IFS= read -r keychain; do
    [[ -n "$keychain" ]] || continue
    if [[ "$keychain" == "$STALE_KEYCHAIN" ]]; then
      removed=1
    else
      retained+=("$keychain")
    fi
  done < <(list_user_keychains)

  if [[ "$removed" -eq 0 ]]; then
    return 0
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "doctor: would remove the obsolete LexiRay release keychain from the user search list."
    return 0
  fi

  # Updating the search list does not unlock, inspect, or delete the stale
  # keychain, so it cannot display the unknown random-password prompt.
  /usr/bin/security list-keychains -d user -s "${retained[@]}"
  echo "doctor: removed the obsolete LexiRay release keychain from the user search list."
}

has_accessible_release_identity() {
  local identities
  [[ -f "$LOCAL_SIGNING_MARKER" ]] || return 1
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :certificate_sha256' "$LOCAL_SIGNING_MARKER" 2>/dev/null || true)" == "$LEXIRAY_RELEASE_CERT_SHA256" ]] || return 1
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :result' "$LOCAL_SIGNING_MARKER" 2>/dev/null || true)" == passed ]] || return 1
  identities="$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null || true)"
  /usr/bin/grep -E "[[:space:]]$LEXIRAY_RELEASE_CERT_SHA1[[:space:]]+\"$IDENTITY_NAME\"" <<<"$identities" >/dev/null &&
    lexiray_has_fixed_release_certificate || return 1
  if ! /usr/bin/swift "$ROOT_DIR/script/probe_release_signing_identity.swift" \
    "$IDENTITY_NAME" "$LEXIRAY_RELEASE_CERT_SHA256" >/dev/null 2>&1; then
    /bin/rm -f "$LOCAL_SIGNING_MARKER"
    echo "doctor: fixed identity is present but not usable without authentication UI; selecting GitHub fallback." >&2
    return 1
  fi
}

require_successful_workflow() {
  local workflow="$1"
  local label="$2"
  local run_fields
  local run_status
  local conclusion
  local head_sha

  if ! run_fields="$(
    gh run list \
      --repo "$REPOSITORY" \
      --workflow "$workflow" \
      --branch main \
      --event push \
      --commit "$SOURCE_COMMIT" \
      --limit 5 \
      --json status,conclusion,headSha,url,databaseId \
      --jq '.[0] | [(.status // ""), (.conclusion // ""), (.headSha // ""), (.databaseId // "" | tostring), (.url // "")] | join("|")'
  )"; then
    die "Could not inspect the $label workflow for $SOURCE_COMMIT."
  fi
  [[ -n "$run_fields" && "$run_fields" != '||||' ]] ||
    die "No $label push run exists for $SOURCE_COMMIT."

  IFS='|' read -r run_status conclusion head_sha GATE_RUN_ID GATE_RUN_URL <<<"$run_fields"
  [[ "$head_sha" == "$SOURCE_COMMIT" ]] || die "$label run SHA does not match the release commit."
  if [[ "$run_status" != completed ]]; then
    echo "doctor: $label is $run_status for $SOURCE_COMMIT: $GATE_RUN_URL" >&2
    echo "doctor: rerun after the main check completes; no release action was taken." >&2
    return 75
  fi
  [[ "$conclusion" == success ]] ||
    die "$label failed with conclusion '$conclusion': $GATE_RUN_URL"
}

receipt_field() {
  "$ROOT_DIR/script/acceptance_receipt.sh" field "$1"
}

require_release_receipt() {
  local receipt_version
  local installed
  local computer_use

  [[ -x "$ROOT_DIR/script/acceptance_receipt.sh" ]] ||
    die "script/acceptance_receipt.sh is missing or not executable."
  "$ROOT_DIR/script/acceptance_receipt.sh" require-handoff
  "$ROOT_DIR/script/acceptance_receipt.sh" require-login-item-probe

  receipt_version="$(receipt_field version)"
  RELEASE_BUILD="$(receipt_field build)"
  SOURCE_FINGERPRINT="$(receipt_field source_fingerprint)"
  installed="$(receipt_field verification.installed)"
  computer_use="$(receipt_field verification.computer_use)"
  CANDIDATE_CERTIFICATE_SHA256="$(receipt_field app.certificate_sha256)"
  CANDIDATE_REQUIREMENT_SHA256="$(receipt_field app.designated_requirement_sha256)"
  CANDIDATE_ENTITLEMENTS_SHA256="$(receipt_field app.entitlements_sha256)"

  [[ "$receipt_version" == "$VERSION" ]] ||
    die "Candidate receipt version is $receipt_version, expected $VERSION."
  [[ "$RELEASE_BUILD" =~ ^[0-9]+$ && "$RELEASE_BUILD" -gt 0 ]] ||
    die "Candidate receipt build must be a positive integer (got $RELEASE_BUILD)."
  [[ "$SOURCE_FINGERPRINT" =~ ^[0-9a-fA-F]{64}$ ]] ||
    die "Candidate receipt has an invalid source fingerprint."
  [[ "$CANDIDATE_CERTIFICATE_SHA256" =~ ^[0-9a-fA-F]{64}$ &&
    "$CANDIDATE_REQUIREMENT_SHA256" =~ ^[0-9a-fA-F]{64}$ &&
    "$CANDIDATE_ENTITLEMENTS_SHA256" =~ ^[0-9a-fA-F]{64}$ ]] ||
    die "Candidate receipt has an incomplete signing-identity binding."
  case "$installed" in
    true|passed) ;;
    *) die "Candidate receipt does not prove the app was installed ($installed)." ;;
  esac
  case "$computer_use" in
    true|passed) ;;
    *) die "Candidate receipt does not prove installed-app Computer Use acceptance ($computer_use)." ;;
  esac
}

doctor() {
  local branch
  local dirty
  local plist_build
  local plist_version
  local remote_main
  local release_commit
  local release_parent_one=""
  local release_parent_two=""
  local release_extra_parent=""
  local workflow_state

  require_command git
  require_command gh
  require_command security
  [[ -x /usr/libexec/PlistBuddy ]] || die "/usr/libexec/PlistBuddy is required."
  [[ -f "$INFO_PLIST" ]] || die "Info.plist not found: $INFO_PLIST"

  cd "$ROOT_DIR"
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Not inside a git worktree."
  lexiray_validate_release_origin "$ROOT_DIR" "$REMOTE" ||
    die "$REMOTE must point at github.com/$REPOSITORY."

  cleanup_stale_keychain_search_list

  dirty="$(git status --porcelain --untracked-files=all)"
  [[ -z "$dirty" ]] || {
    echo "$dirty" >&2
    die "Working tree must be clean before release publication."
  }

  SOURCE_COMMIT="$(git rev-parse HEAD)"
  TAG_COMMIT="$(remote_tag_commit)"
  [[ -n "$TAG_COMMIT" ]] || die "Remote tag $TAG does not exist on $REMOTE."

  remote_main="$(gh api "repos/$REPOSITORY/commits/main" --jq '.sha' 2>/dev/null || true)"
  [[ -n "$remote_main" ]] || die "Could not resolve $REMOTE/main."
  [[ "$TAG_COMMIT" == "$remote_main" ]] ||
    die "$TAG must point at $REMOTE/main before publication ($TAG_COMMIT != $remote_main)."
  [[ "$SOURCE_COMMIT" == "$TAG_COMMIT" ]] ||
    die "Local HEAD must match $TAG ($SOURCE_COMMIT != $TAG_COMMIT)."

  release_commit="$(git rev-list --parents -n 1 "$TAG_COMMIT")"
  read -r release_commit release_parent_one release_parent_two release_extra_parent \
    <<<"$release_commit"
  [[ "$release_commit" == "$TAG_COMMIT" && -n "$release_parent_one" &&
    -n "$release_parent_two" && -z "$release_extra_parent" ]] ||
    die "$TAG must point at a two-parent dev-to-main release merge commit."

  branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  if [[ -n "$branch" && "$branch" != "main" ]]; then
    die "Release publication must run from main or a detached $TAG checkout, not $branch."
  fi

  plist_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
  plist_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
  [[ "$plist_version" == "$VERSION" ]] ||
    die "Info.plist version is $plist_version, expected $VERSION."
  require_release_receipt
  [[ "$plist_build" =~ ^[0-9]+$ && "$plist_build" -gt 0 ]] ||
    die "Info.plist build must be a positive integer (got $plist_build)."
  [[ "$plist_build" == "$RELEASE_BUILD" ]] ||
    die "Info.plist build is $plist_build, candidate receipt build is $RELEASE_BUILD."
  /usr/bin/grep -F "## [$VERSION]" "$ROOT_DIR/CHANGELOG.md" >/dev/null ||
    die "CHANGELOG.md must contain a section for $VERSION."

  gh auth status >/dev/null 2>&1 || die "gh is not authenticated."
  STATE_KEY="${TAG}-${SOURCE_COMMIT:0:12}"
  STATE_FILE="$(state_path_for_commit "$SOURCE_COMMIT")"
  acquire_publish_lock
  require_successful_workflow ci.yml CI
  CI_RUN_ID="$GATE_RUN_ID"
  CI_RUN_URL="$GATE_RUN_URL"

  if has_accessible_release_identity; then
    require_command xcodegen
    require_command xcodebuild
    [[ -x /usr/bin/hdiutil ]] || die "/usr/bin/hdiutil is required."
    RELEASE_MODE=local
    echo "doctor: fixed release identity is accessible; local publication selected."
  else
    workflow_state="$(
      gh api "repos/$REPOSITORY/actions/workflows/$WORKFLOW" --jq '.state' 2>/dev/null || true
    )"
    [[ "$workflow_state" == active ]] ||
      die "GitHub fallback workflow is unavailable: $WORKFLOW"
    RELEASE_MODE=fallback
    echo "doctor: fixed release identity is not accessible; GitHub Release Build fallback selected."
  fi

  initialize_state
  state_set mode "$RELEASE_MODE"
  state_set ci_run_id "$CI_RUN_ID"
  state_set ci_run_url "$CI_RUN_URL"
  state_set doctor complete
  state_set doctor_completed_at "$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)"

  echo "doctor: $TAG is ready at $SOURCE_COMMIT."
  if [[ "$DRY_RUN" -eq 0 ]]; then
    echo "doctor: state $STATE_FILE"
  fi
}

verify_published_assets() {
  local dmg_name="LexiRay-$VERSION.dmg"
  local sha_name="$dmg_name.sha256"
  local assets
  local metadata
  local tmp_dir
  local release_url

  if ! metadata="$(
    gh release list \
      --repo "$REPOSITORY" \
      --limit 100 \
      --json tagName,name,body,isDraft,isPrerelease \
      --jq "map(select(.tagName == \"$TAG\")) | if length == 0 then \"absent\" elif (.[0].name == \"LexiRay $VERSION\" and (.[0].isDraft == false) and (.[0].isPrerelease == false) and ((.[0].body // \"\") | contains(\"self-signed, non-notarized\")) and ((.[0].body // \"\") | contains(\"Gatekeeper\")) and ((.[0].body // \"\") | contains(\".sha256\"))) then \"ready\" else \"incomplete\" end"
  )"; then
    echo "release: GitHub release metadata is temporarily unavailable." >&2
    return "$ASSET_UNCERTAIN"
  fi
  [[ "$metadata" == ready ]] || return "$ASSET_ABSENT"

  if ! assets="$(
    gh release view "$TAG" --repo "$REPOSITORY" --json assets --jq '.assets[].name'
  )"; then
    echo "release: GitHub release assets are temporarily unavailable." >&2
    return "$ASSET_UNCERTAIN"
  fi
  /usr/bin/grep -Fx "$dmg_name" <<<"$assets" >/dev/null || return "$ASSET_ABSENT"
  /usr/bin/grep -Fx "$sha_name" <<<"$assets" >/dev/null || return "$ASSET_ABSENT"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "status: would download and verify $dmg_name and $sha_name."
    return 0
  fi

  tmp_dir="$(/usr/bin/mktemp -d)"
  if ! gh release download "$TAG" \
    --repo "$REPOSITORY" \
    --pattern "$dmg_name" \
    --pattern "$sha_name" \
    --dir "$tmp_dir" \
    --clobber >/dev/null; then
    rm -rf "$tmp_dir"
    return "$ASSET_UNCERTAIN"
  fi
  if ! lexiray_verify_sha256_file "$tmp_dir/$sha_name" "$tmp_dir/$dmg_name" "$dmg_name"; then
    echo "release: downloaded SHA-256 file is malformed or does not match $dmg_name." >&2
    rm -rf "$tmp_dir"
    return "$ASSET_INVALID"
  fi
  if ! "$ROOT_DIR/script/verify_release_dmg.sh" \
    "$tmp_dir/$dmg_name" "$VERSION" "$RELEASE_BUILD" "$SOURCE_COMMIT" "$SOURCE_FINGERPRINT"; then
    rm -rf "$tmp_dir"
    return "$ASSET_INVALID"
  fi
  rm -rf "$tmp_dir"

  if ! release_url="$(gh release view "$TAG" --repo "$REPOSITORY" --json url --jq '.url')"; then
    return "$ASSET_UNCERTAIN"
  fi
  state_set assets_verified complete
  state_set release complete
  state_set release_url "$release_url"
  state_set completed_at "$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "release: verified $TAG assets: $release_url"
}

find_fallback_run() {
  local dispatch_id
  local run_name
  local runs
  dispatch_id="$(state_get fallback_dispatch_id 2>/dev/null || true)"
  [[ "$dispatch_id" =~ ^[0-9a-f-]{36}$ ]] || return 1
  run_name="Release Build $TAG [$STATE_KEY/$dispatch_id]"
  if ! runs="$(
    gh run list \
      --repo "$REPOSITORY" \
      --workflow "$WORKFLOW" \
      --event workflow_dispatch \
      --limit 50 \
      --json databaseId,displayTitle,headSha \
      --jq ".[] | select(.displayTitle == \"$run_name\" and .headSha == \"$TAG_COMMIT\") | .databaseId" 2>/dev/null
  )"; then
    return "$ASSET_UNCERTAIN"
  fi
  /usr/bin/head -n 1 <<<"$runs"
}

dispatch_fallback() {
  local run_id
  local run_query_status
  local attempt
  local dispatch_id

  if [[ "$(state_get fallback_dispatched 2>/dev/null || true)" == "complete" ]]; then
    status_release
    return
  fi

  attempt="$(state_get fallback_attempt 2>/dev/null || echo 0)"
  [[ "$attempt" =~ ^[0-9]+$ ]] || die "Fallback attempt counter is invalid."
  attempt=$((attempt + 1))

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "publish: would dispatch $WORKFLOW for $TAG with a new unique dispatch ID."
    return 0
  fi

  dispatch_id="$(/usr/bin/uuidgen | /usr/bin/tr '[:upper:]' '[:lower:]')"
  state_set fallback_attempt "$attempt"
  state_set fallback_dispatch_id "$dispatch_id"
  state_set fallback_dispatch_started_at "$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)"
  state_set fallback_dispatch_started_epoch "$(/bin/date +%s)"
  state_delete workflow_run_id
  state_delete workflow_url
  # Persist ambiguity before the API call. If this process is killed after
  # GitHub accepts the dispatch, a resume discovers the correlated run instead
  # of starting a duplicate.
  state_set fallback_dispatch uncertain
  state_set fallback_dispatched uncertain
  if ! gh workflow run "$WORKFLOW" \
    --repo "$REPOSITORY" \
    --ref main \
    -f "version=$VERSION" \
    -f "state_key=$STATE_KEY" \
    -f "dispatch_id=$dispatch_id"; then
    state_set fallback_dispatch uncertain
    die "Fallback dispatch failed or its result is uncertain. Run '$0 status $VERSION' before retrying."
  fi

  state_set fallback_dispatched complete
  state_set fallback_dispatch complete
  state_set fallback_dispatched_at "$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)"
  set +e
  run_id="$(find_fallback_run)"
  run_query_status=$?
  set -e
  if [[ "$run_query_status" -eq 0 && -n "$run_id" ]]; then
    state_set workflow_run_id "$run_id"
  elif [[ "$run_query_status" -eq "$ASSET_UNCERTAIN" ]]; then
    echo "publish: fallback was accepted, but its run is not queryable yet; resume with status." >&2
  fi

  echo "publish: fallback dispatched for $TAG."
  echo "publish: resume with: $0 status $VERSION"
  return 75
}

publish_local() {
  local asset_result
  local dmg_path="$ROOT_DIR/build/LexiRay-$VERSION.dmg"
  local sha_path="$dmg_path.sha256"

  if verify_published_assets; then
    echo "publish: the required assets were already published; no steps repeated."
    return 0
  else
    asset_result=$?
  fi
  if [[ "$asset_result" -eq "$ASSET_UNCERTAIN" ]]; then
    echo "publish: GitHub release state is temporarily unavailable; retry publish without changing local artifacts." >&2
    return 75
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "publish: would package locally, verify the fixed signature, upload the DMG and SHA-256, then verify downloaded assets."
    return 0
  fi

  create_release_capability local
  if [[ "$(state_get local_package 2>/dev/null || true)" != "complete" ]] ||
    [[ ! -s "$dmg_path" || ! -s "$sha_path" ]]; then
    LEXIRAY_RELEASE_ORCHESTRATED=local \
      LEXIRAY_RELEASE_NO_UI=1 \
      LEXIRAY_RELEASE_SOURCE_COMMIT="$SOURCE_COMMIT" \
      LEXIRAY_RELEASE_SOURCE_FINGERPRINT="$SOURCE_FINGERPRINT" \
      "$ROOT_DIR/script/package_release_dmg.sh" "$VERSION"
    "$ROOT_DIR/script/verify_release_dmg.sh" \
      "$dmg_path" "$VERSION" "$RELEASE_BUILD" "$SOURCE_COMMIT" "$SOURCE_FINGERPRINT"
    lexiray_verify_sha256_file "$sha_path" "$dmg_path" "$(basename "$dmg_path")" ||
      die "Local SHA-256 file is malformed or does not match the DMG."
    state_set local_package complete
    state_set local_package_completed_at "$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)"
  else
    "$ROOT_DIR/script/verify_release_dmg.sh" \
      "$dmg_path" "$VERSION" "$RELEASE_BUILD" "$SOURCE_COMMIT" "$SOURCE_FINGERPRINT"
    lexiray_verify_sha256_file "$sha_path" "$dmg_path" "$(basename "$dmg_path")" ||
      die "Recorded local package no longer matches its SHA-256 file."
    echo "publish: reusing the verified local package recorded in $STATE_FILE."
  fi

  create_release_capability local
  LEXIRAY_RELEASE_ORCHESTRATED=local \
    "$ROOT_DIR/script/publish_release.sh" "$VERSION" --skip-package
  state_set assets_uploaded complete
  state_set assets_uploaded_at "$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)"
  if verify_published_assets; then
    :
  else
    asset_result=$?
    case "$asset_result" in
      "$ASSET_INVALID") die "Published assets failed independent verification." ;;
      *)
        echo "publish: upload completed, but GitHub asset visibility is not yet verifiable." >&2
        echo "publish: resume with: $0 status $VERSION" >&2
        return 75
        ;;
    esac
  fi
}

confirm_fallback_artifact() {
  local run_id="$1"
  local dispatch_id
  local artifact_name
  local tmp_dir dmg_name sha_name dmg_path sha_path
  local state_fingerprint="$SOURCE_FINGERPRINT"
  local state_build="$RELEASE_BUILD"
  local state_candidate_certificate state_candidate_requirement state_candidate_entitlements

  [[ "$RELEASE_TEST_MODE" == 0 ]] ||
    die "Release test mode cannot download, confirm, or publish fallback artifacts."

  dispatch_id="$(state_get fallback_dispatch_id 2>/dev/null || true)"
  [[ "$dispatch_id" =~ ^[0-9a-f-]{36}$ ]] || die "Fallback dispatch ID is missing or invalid."
  artifact_name="$FALLBACK_ARTIFACT_PREFIX-$STATE_KEY-$dispatch_id"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "status: would download, verify, and locally confirm fallback artifact $artifact_name."
    return 0
  fi

  # A remote builder is allowed to produce only a signed artifact. Re-check the
  # local installed-app/CU handoff immediately before that artifact can become
  # a public GitHub Release.
  state_candidate_certificate="$(state_get candidate_certificate_sha256)"
  state_candidate_requirement="$(state_get candidate_designated_requirement_sha256)"
  state_candidate_entitlements="$(state_get candidate_entitlements_sha256)"
  require_release_receipt >/dev/null
  [[ "$SOURCE_FINGERPRINT" == "$state_fingerprint" && "$RELEASE_BUILD" == "$state_build" &&
    "$CANDIDATE_CERTIFICATE_SHA256" == "$state_candidate_certificate" &&
    "$CANDIDATE_REQUIREMENT_SHA256" == "$state_candidate_requirement" &&
    "$CANDIDATE_ENTITLEMENTS_SHA256" == "$state_candidate_entitlements" ]] ||
    die "Current local acceptance no longer matches the fallback release state."

  tmp_dir="$(/usr/bin/mktemp -d)"
  dmg_name="LexiRay-$VERSION.dmg"
  sha_name="$dmg_name.sha256"
  if ! gh run download "$run_id" \
    --repo "$REPOSITORY" \
    --name "$artifact_name" \
    --dir "$tmp_dir" >/dev/null; then
    rm -rf "$tmp_dir"
    echo "status: fallback artifact is not downloadable yet; state remains uncertain." >&2
    return "$ASSET_UNCERTAIN"
  fi
  dmg_path="$tmp_dir/$dmg_name"
  sha_path="$tmp_dir/$sha_name"
  if ! lexiray_verify_sha256_file "$sha_path" "$dmg_path" "$dmg_name" ||
    ! "$ROOT_DIR/script/verify_release_dmg.sh" \
      "$dmg_path" "$VERSION" "$RELEASE_BUILD" "$SOURCE_COMMIT" "$SOURCE_FINGERPRINT"; then
    rm -rf "$tmp_dir"
    state_set fallback_dispatch failed
    state_set fallback_dispatched failed
    die "Fallback artifact is present but failed checksum, signature, identity, or source verification."
  fi
  mkdir -p "$ROOT_DIR/build"
  /usr/bin/ditto "$dmg_path" "$ROOT_DIR/build/$dmg_name"
  /usr/bin/ditto "$sha_path" "$ROOT_DIR/build/$sha_name"
  rm -rf "$tmp_dir"
  state_set fallback_artifact_verified complete
  state_set fallback_artifact_run_id "$run_id"
  create_release_capability fallback-confirm
  LEXIRAY_RELEASE_ORCHESTRATED=fallback-confirm \
    "$ROOT_DIR/script/publish_release.sh" "$VERSION" --skip-package
  state_set assets_uploaded complete
}

publish_release() {
  local asset_result
  local existing_dispatch

  doctor

  existing_dispatch="$(state_get fallback_dispatch 2>/dev/null || true)"
  if [[ "$existing_dispatch" == complete || "$existing_dispatch" == uncertain ]]; then
    # Never race a local upload against a fallback that may already be running.
    state_set mode fallback
    status_release
    return
  fi

  if [[ "$RELEASE_MODE" == local ]]; then
    publish_local
  else
    if verify_published_assets; then
      echo "publish: the required assets were already published; no fallback dispatched."
      return 0
    else
      asset_result=$?
    fi
    if [[ "$asset_result" -eq "$ASSET_UNCERTAIN" ]]; then
      echo "publish: GitHub release state is temporarily unavailable; no fallback was dispatched." >&2
      return 75
    fi
    dispatch_fallback
  fi
}

load_status_context() {
  require_command git
  require_command gh
  cd "$ROOT_DIR"
  lexiray_validate_release_origin "$ROOT_DIR" "$REMOTE" ||
    die "$REMOTE must point at github.com/$REPOSITORY."

  TAG_COMMIT="$(remote_tag_commit)"
  [[ -n "$TAG_COMMIT" ]] || die "Remote tag $TAG does not exist on $REMOTE."
  SOURCE_COMMIT="$TAG_COMMIT"
  STATE_KEY="${TAG}-${SOURCE_COMMIT:0:12}"
  STATE_FILE="$(state_path_for_commit "$SOURCE_COMMIT")"
  [[ -f "$STATE_FILE" ]] || die "No release state found for $TAG at $SOURCE_COMMIT."

  [[ "$(state_get version)" == "$VERSION" ]] || die "Release state version mismatch."
  RELEASE_BUILD="$(state_get build)"
  [[ "$RELEASE_BUILD" =~ ^[0-9]+$ && "$RELEASE_BUILD" -gt 0 ]] ||
    die "Release state build is invalid."
  [[ "$(state_get tag)" == "$TAG" ]] || die "Release state tag-name mismatch."
  [[ "$(state_get source_commit)" == "$SOURCE_COMMIT" ]] || die "Release state source mismatch."
  [[ "$(state_get tag_commit)" == "$TAG_COMMIT" ]] || die "Release state tag mismatch."
  [[ "$(state_get certificate_sha256)" == "$LEXIRAY_RELEASE_CERT_SHA256" ]] ||
    die "Release state certificate fingerprint mismatch."
  [[ "$(state_get candidate_certificate_sha256)" =~ ^[0-9a-fA-F]{64}$ &&
    "$(state_get candidate_designated_requirement_sha256)" =~ ^[0-9a-fA-F]{64}$ &&
    "$(state_get candidate_entitlements_sha256)" =~ ^[0-9a-fA-F]{64}$ ]] ||
    die "Release state candidate identity binding is incomplete."
  [[ "$(state_get state_key)" == "$STATE_KEY" ]] || die "Release state correlation-key mismatch."
  [[ "$(state_get source_fingerprint)" =~ ^[0-9a-fA-F]{64}$ ]] ||
    die "Release state source fingerprint is invalid."
  SOURCE_FINGERPRINT="$(state_get source_fingerprint)"
}

status_release() {
  local asset_result
  local dispatch_age
  local dispatch_epoch
  local dispatch_state
  local run_id
  local run_fields
  local run_status
  local conclusion
  local run_url
  local head_sha
  local release_mode
  local run_query_status

  load_status_context
  acquire_publish_lock
  load_status_context

  if [[ "$(state_get release 2>/dev/null || true)" == "complete" ]]; then
    echo "status: $TAG is complete."
    echo "status: $(state_get release_url 2>/dev/null || true)"
    return 0
  fi

  dispatch_state="$(state_get fallback_dispatch 2>/dev/null || true)"
  release_mode="$(state_get mode 2>/dev/null || true)"
  if [[ "$dispatch_state" == complete || "$dispatch_state" == uncertain || "$dispatch_state" == failed ]]; then
    [[ "$(state_get fallback_dispatch_id 2>/dev/null || true)" =~ ^[0-9a-f-]{36}$ ]] ||
      die "Fallback dispatch state has no valid unique dispatch ID."
  fi
  if [[ "$release_mode" == local && "$dispatch_state" != complete && "$dispatch_state" != uncertain ]]; then
    if verify_published_assets; then
      return 0
    else
      asset_result=$?
    fi
    if [[ "$asset_result" -eq "$ASSET_UNCERTAIN" ]]; then
      echo "status: GitHub release state is temporarily unavailable; retry status." >&2
      return 75
    fi
    die "Local publication is incomplete or invalid. Resume with '$0 publish $VERSION'."
  fi

  run_id="$(state_get workflow_run_id 2>/dev/null || true)"
  if [[ -z "$run_id" ]]; then
    set +e
    run_id="$(find_fallback_run)"
    run_query_status=$?
    set -e
    if [[ "$run_query_status" -eq "$ASSET_UNCERTAIN" ]]; then
      echo "status: GitHub workflow lookup is temporarily unavailable; dispatch state remains uncertain." >&2
      return 75
    fi
    if [[ -n "$run_id" ]]; then
      state_set workflow_run_id "$run_id"
    fi
  fi

  if [[ -z "$run_id" ]]; then
    case "$dispatch_state" in
      complete|uncertain)
        dispatch_epoch="$(state_get fallback_dispatch_started_epoch 2>/dev/null || true)"
        if [[ "$dispatch_epoch" =~ ^[0-9]+$ ]]; then
          dispatch_age=$(( $(/bin/date +%s) - dispatch_epoch ))
          if [[ "$dispatch_age" -ge 300 ]]; then
            echo "status: no correlated fallback run is visible after five minutes; dispatch remains uncertain." >&2
          fi
        fi
        echo "status: fallback dispatch is recorded, but GitHub has not exposed the run yet."
        echo "status: retry this command; no new workflow was dispatched."
        return 75
        ;;
      failed)
        die "The last fallback failed. Fix its logged cause, then run '$0 publish $VERSION'."
        ;;
      *)
        die "No fallback dispatch is recorded. Run '$0 publish $VERSION' first."
        ;;
    esac
  fi

  if ! run_fields="$(gh run view "$run_id" \
    --repo "$REPOSITORY" \
    --json status,conclusion,url,headSha \
    --jq '[.status, (.conclusion // ""), .url, .headSha] | join("|")')"; then
    echo "status: fallback run visibility is temporarily unavailable; state remains uncertain." >&2
    return 75
  fi
  IFS='|' read -r run_status conclusion run_url head_sha <<<"$run_fields"
  state_set workflow_run_id "$run_id"
  state_set workflow_url "$run_url"
  if [[ "$head_sha" != "$TAG_COMMIT" ]]; then
    state_set fallback_dispatch failed
    state_set fallback_dispatched failed
    die "Fallback run uses $head_sha, expected tag commit $TAG_COMMIT."
  fi

  case "$run_status" in
    queued|in_progress|pending|requested|waiting)
      echo "status: fallback is $run_status: $run_url"
      echo "status: resume with: $0 status $VERSION"
      return 75
      ;;
    completed)
      if [[ "$conclusion" != success ]]; then
        state_set fallback_dispatch failed
        state_set fallback_dispatched failed
        state_set last_failed_run_id "$run_id"
        state_set last_failure_conclusion "${conclusion:-unknown}"
        echo "status: fallback failed ($conclusion): $run_url" >&2
        echo "status: failed-step log follows:" >&2
        gh run view "$run_id" --repo "$REPOSITORY" --log-failed >&2 || true
        echo "status: fix the logged cause, then rerun '$0 publish $VERSION'; completed steps will be reused." >&2
        return 1
      fi
      ;;
    *)
      die "Unexpected workflow status '$run_status' for $run_url."
      ;;
  esac

  if [[ "$(state_get fallback_completed 2>/dev/null || true)" != complete ]]; then
    state_set fallback_completed complete
    state_set fallback_completed_at "$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)"
    state_set fallback_completed_epoch "$(/bin/date +%s)"
  fi


  if verify_published_assets; then
    return 0
  else
    asset_result=$?
  fi
  if [[ "$asset_result" -eq "$ASSET_UNCERTAIN" ]]; then
    echo "status: fallback succeeded; GitHub release state is temporarily unavailable." >&2
    return 75
  fi
  if confirm_fallback_artifact "$run_id"; then
    :
  else
    asset_result=$?
    [[ "$asset_result" -eq "$ASSET_UNCERTAIN" ]] && return 75
    return "$asset_result"
  fi
  [[ "$DRY_RUN" -eq 0 ]] || return 0

  if verify_published_assets; then
    :
  else
    asset_result=$?
    case "$asset_result" in
      "$ASSET_UNCERTAIN")
        echo "status: fallback succeeded; GitHub asset verification is temporarily unavailable." >&2
        return 75
        ;;
      "$ASSET_ABSENT")
        echo "status: fallback publication is not visible yet; state remains uncertain." >&2
        return 75
        ;;
    esac
    state_set assets_verified failed
    state_set fallback_dispatch failed
    state_set fallback_dispatched failed
    die "Fallback succeeded, but the published DMG/SHA assets are confirmed missing or invalid. Inspect $run_url, fix the cause, then rerun publish."
  fi
}

if [[ $# -lt 2 || $# -gt 3 ]]; then
  usage >&2
  exit 2
fi

COMMAND="$1"
VERSION="$2"
if [[ $# -eq 3 ]]; then
  [[ "$3" == --dry-run ]] || {
    usage >&2
    exit 2
  }
  DRY_RUN=1
fi

if [[ "$RELEASE_TEST_MODE" == 1 ]]; then
  test_root="$(dirname "$STATE_DIR")"
  [[ "$COMMAND" == status && "${LEXIRAY_RELEASE_TEST_HARNESS:-}" == 1 &&
    -f "$test_root/.lexiray-release-test-harness" &&
    "$STATE_DIR" == "$test_root/state" && "$GLOBAL_LOCK_FILE" == "$test_root/release-lock/lock" &&
    "${LEXIRAY_RELEASE_TEST_BIN_DIR:-}" == "$test_root/bin" &&
    "$(command -v gh 2>/dev/null || true)" == "$test_root/bin/gh" &&
    "$(command -v git 2>/dev/null || true)" == "$test_root/bin/git" ]] || {
    echo "release: test mode is restricted to the isolated no-network status harness." >&2
    exit 1
  }
fi

bootstrap_publish_lock "$@"
validate_version
TAG="v$VERSION"
SOURCE_COMMIT=""
TAG_COMMIT=""
SOURCE_FINGERPRINT=""
CANDIDATE_CERTIFICATE_SHA256=""
CANDIDATE_REQUIREMENT_SHA256=""
CANDIDATE_ENTITLEMENTS_SHA256=""
STATE_KEY=""
STATE_FILE=""
RELEASE_MODE=""
RELEASE_BUILD=""
GATE_RUN_ID=""
GATE_RUN_URL=""
CI_RUN_ID=""
CI_RUN_URL=""

case "$COMMAND" in
  doctor) doctor ;;
  publish) publish_release ;;
  status) status_release ;;
  *)
    usage >&2
    exit 2
    ;;
esac

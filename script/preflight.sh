#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

case "$MODE" in
  change|release) ;;
  *) echo "usage: $0 change|release" >&2; exit 2 ;;
esac

cd "$ROOT_DIR"

fail() {
  echo "PREFLIGHT_ERROR[$MODE]: $*" >&2
  exit 1
}

warn() {
  echo "PREFLIGHT_WARN[$MODE]: $*" >&2
}

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "not inside a git worktree"

required_tools=(git rg xcodebuild xcodegen swiftformat codesign shasum)
missing_tools=()
for tool in "${required_tools[@]}"; do
  command -v "$tool" >/dev/null 2>&1 || missing_tools+=("$tool")
done
[[ ${#missing_tools[@]} -eq 0 ]] || fail "missing tools: ${missing_tools[*]}"
[[ -x /usr/libexec/PlistBuddy ]] || fail "/usr/libexec/PlistBuddy is unavailable"

for state_dir in rebase-merge rebase-apply MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD; do
  state_path="$(git rev-parse --git-path "$state_dir")"
  [[ ! -e "$state_path" ]] || fail "git operation is in progress: $state_dir"
done

branch="$(git symbolic-ref --quiet --short HEAD || true)"
[[ -n "$branch" ]] || fail "detached HEAD is not a supported working state"

require_current_local_dev() {
  git rev-parse --verify dev >/dev/null 2>&1 || fail "local dev is unavailable"
  if git rev-parse --verify origin/dev >/dev/null 2>&1; then
    git merge-base --is-ancestor origin/dev dev ||
      fail "local dev is behind or divergent from the currently known origin/dev"
  fi
  if git rev-parse --verify origin/main >/dev/null 2>&1; then
    git merge-base --is-ancestor origin/main dev ||
      fail "local dev does not contain the currently known origin/main release"
  fi
}

local_dev_is_current() {
  git rev-parse --verify dev >/dev/null 2>&1 || return 1
  if git rev-parse --verify origin/dev >/dev/null 2>&1; then
    git merge-base --is-ancestor origin/dev dev || return 1
  fi
  if git rev-parse --verify origin/main >/dev/null 2>&1; then
    git merge-base --is-ancestor origin/main dev || return 1
  fi
}

case "$MODE:$branch" in
  change:feat/*|change:fix/*|change:chore/*|change:docs/*) ;;
  change:dev) fail "work must not run directly on dev; create feat/, fix/, chore/, or docs/<task>" ;;
  change:main) fail "ordinary changes must not run directly on main" ;;
  change:*) fail "branch '$branch' does not follow feat|fix|chore|docs/<task>" ;;
  release:dev|release:main|release:fix/*) ;;
  release:*) fail "release preflight must run on dev, main, or an emergency fix/<task> branch" ;;
esac

if [[ "$branch" == feat/* || "$branch" == chore/* || "$branch" == docs/* ]]; then
  if git rev-parse --verify dev >/dev/null 2>&1; then
    require_current_local_dev
    git merge-base --is-ancestor dev HEAD ||
      fail "task branch is not based on the current local dev"
  elif git rev-parse --verify origin/dev >/dev/null 2>&1; then
    git merge-base --is-ancestor origin/dev HEAD ||
      fail "task branch is not based on the currently known origin/dev"
  else
    fail "neither local dev nor origin/dev is available for task-branch ancestry checks"
  fi
fi

if [[ "$branch" == fix/* ]]; then
  if git rev-parse --verify dev >/dev/null 2>&1 &&
    git merge-base --is-ancestor dev HEAD &&
    local_dev_is_current; then
    :
  elif git rev-parse --verify origin/main >/dev/null 2>&1 &&
    git merge-base --is-ancestor origin/main HEAD; then
    warn "fix branch is based on main; treating it as an emergency hotfix that must be synced back to dev"
  else
    fail "fix branch is based on neither the currently known origin/dev nor origin/main"
  fi
fi

dirty="$(git status --porcelain --untracked-files=all)"
if [[ "$MODE" == release && -n "$dirty" ]]; then
  echo "$dirty" >&2
  fail "release preflight requires a clean worktree"
fi
if [[ "$MODE" == change && -n "$dirty" ]]; then
  changed_count="$(printf '%s\n' "$dirty" | wc -l | tr -d ' ')"
  echo "PREFLIGHT_INFO[change]: $changed_count working-tree path(s) currently changed"
fi

running_paths="$(
  (pgrep -x LexiRay || true) |
    while IFS= read -r pid; do
      [[ -n "$pid" ]] || continue
      ps -p "$pid" -o args=
    done
)"
if [[ -n "$running_paths" ]]; then
  while IFS= read -r process_path; do
    [[ -n "$process_path" ]] || continue
    case "$process_path" in
      "$ROOT_DIR"/build/*/LexiRay.app/Contents/MacOS/LexiRay*)
        warn "workspace LexiRay is already running; GUI verification will block rather than terminate it"
        ;;
      *) warn "non-workspace LexiRay is running: $process_path" ;;
    esac
  done <<<"$running_paths"
fi

if [[ "$MODE" == release ]]; then
  git remote get-url origin >/dev/null 2>&1 || fail "origin remote is unavailable"
  "$ROOT_DIR/script/acceptance_receipt.sh" require-candidate >/dev/null ||
    fail "current source has no valid candidate acceptance receipt"
  echo "PREFLIGHT_INFO[release]: keychain access intentionally skipped; use release doctor for signing availability"
fi

echo "PREFLIGHT_PASS[$MODE]: branch=$branch"

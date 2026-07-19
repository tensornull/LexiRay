#!/usr/bin/env bash
set -euo pipefail

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/lexiray-git-flow.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REMOTE="$TMP_ROOT/remote.git"
WORK="$TMP_ROOT/work"
FLOW_BIN_DIR="$TMP_ROOT/bin"
FLOW_SWIFTFORMAT_TOOL="$TMP_ROOT/swiftformat"

mkdir -p "$FLOW_BIN_DIR"
cat >"$FLOW_BIN_DIR/xcodegen" <<'XCODEGEN'
#!/usr/bin/env bash
exit 0
XCODEGEN
chmod +x "$FLOW_BIN_DIR/xcodegen"
export PATH="$FLOW_BIN_DIR:$PATH"

cat >"$FLOW_SWIFTFORMAT_TOOL" <<'SWIFTFORMAT'
#!/usr/bin/env bash
if [[ "${1:-}" == --version ]]; then
  echo "0.62.1"
fi
SWIFTFORMAT
chmod +x "$FLOW_SWIFTFORMAT_TOOL"

install_preflight_fixture() {
  local fixture_root="$1"
  mkdir -p "$fixture_root/script"
  cp "$ROOT_DIR/script/preflight.sh" "$fixture_root/script/preflight.sh"
  cp "$ROOT_DIR/script/swiftformat_tool.sh" "$fixture_root/script/swiftformat_tool.sh"
  chmod +x "$fixture_root/script/preflight.sh" "$fixture_root/script/swiftformat_tool.sh"
}

git init --bare -q "$REMOTE"
git init -q -b main "$WORK"
git -C "$WORK" config user.name "LexiRay Flow Test"
git -C "$WORK" config user.email "flow-test@lexiray.invalid"
git -C "$WORK" remote add origin "$REMOTE"

printf 'initial\n' >"$WORK/state.txt"
git -C "$WORK" add state.txt
git -C "$WORK" commit -qm initial
git -C "$WORK" push -qu origin main

git -C "$WORK" switch -qc dev
git -C "$WORK" push -qu origin dev
git -C "$WORK" switch -qc feat/demo
printf 'feature\n' >>"$WORK/state.txt"
git -C "$WORK" commit -qam feature

git -C "$WORK" switch -q dev
git -C "$WORK" merge --squash feat/demo >/dev/null
git -C "$WORK" commit -qm 'feat: demo'
[[ "$(git -C "$WORK" rev-list --count main..dev)" == 1 ]]

git -C "$WORK" switch -q main
git -C "$WORK" merge --no-ff dev -m 'release: demo' >/dev/null
[[ "$(git -C "$WORK" rev-list --parents -n 1 HEAD | awk '{print NF}')" == 3 ]]
git -C "$WORK" push -qu origin main

git -C "$WORK" switch -q dev
git -C "$WORK" merge --ff-only main >/dev/null
[[ "$(git -C "$WORK" rev-parse dev)" == "$(git -C "$WORK" rev-parse main)" ]]
git -C "$WORK" push -qu origin dev

git -C "$WORK" switch -qc fix/emergency main
printf 'hotfix\n' >>"$WORK/state.txt"
git -C "$WORK" commit -qam hotfix
git -C "$WORK" switch -q main
git -C "$WORK" merge --no-ff fix/emergency -m 'fix: emergency' >/dev/null
git -C "$WORK" switch -q dev
git -C "$WORK" merge --ff-only main >/dev/null
[[ "$(git -C "$WORK" rev-parse dev)" == "$(git -C "$WORK" rev-parse main)" ]]

# Advance origin/dev, then prove a task branch from the stale local dev is
# rejected until local dev is fast-forwarded to the known remote tip.
stale_dev="$(git -C "$WORK" rev-parse dev)"
printf 'remote integration\n' >>"$WORK/state.txt"
git -C "$WORK" commit -qam 'chore: remote integration'
git -C "$WORK" push -qu origin dev
git -C "$WORK" switch -q main
git -C "$WORK" branch -f dev "$stale_dev"
git -C "$WORK" branch chore/stale-dev "$stale_dev"
install_preflight_fixture "$WORK"
git -C "$WORK" branch -f chore/stale-dev "$stale_dev"
git -C "$WORK" worktree add -q "$TMP_ROOT/stale-task" chore/stale-dev
install_preflight_fixture "$TMP_ROOT/stale-task"

if (cd "$TMP_ROOT/stale-task" && LEXIRAY_SWIFTFORMAT_TOOL="$FLOW_SWIFTFORMAT_TOOL" \
  ./script/preflight.sh change >"$TMP_ROOT/stale-preflight.log" 2>&1); then
  echo "preflight accepted a task branch based on stale local dev" >&2
  exit 1
fi
rg -F 'local dev is behind or divergent from the currently known origin/dev' \
  "$TMP_ROOT/stale-preflight.log" >/dev/null || {
  cat "$TMP_ROOT/stale-preflight.log" >&2
  echo "preflight did not report the stale local dev cause" >&2
  exit 1
}

git -C "$WORK" branch -f dev origin/dev
git -C "$WORK" branch chore/current-dev dev
git -C "$WORK" worktree add -q "$TMP_ROOT/current-task" chore/current-dev
install_preflight_fixture "$TMP_ROOT/current-task"
(cd "$TMP_ROOT/current-task" && LEXIRAY_SWIFTFORMAT_TOOL="$FLOW_SWIFTFORMAT_TOOL" \
  ./script/preflight.sh change >/dev/null)

git -C "$WORK" switch -qc chore/primary-check dev
install_preflight_fixture "$WORK"
if (cd "$WORK" && LEXIRAY_SWIFTFORMAT_TOOL="$FLOW_SWIFTFORMAT_TOOL" \
  ./script/preflight.sh change >"$TMP_ROOT/primary-preflight.log" 2>&1); then
  echo "preflight accepted ordinary work in the primary checkout" >&2
  exit 1
fi
rg -F 'ordinary changes require a dedicated linked worktree' \
  "$TMP_ROOT/primary-preflight.log" >/dev/null || {
  cat "$TMP_ROOT/primary-preflight.log" >&2
  echo "preflight did not report the primary-checkout cause" >&2
  exit 1
}

git -C "$WORK" worktree add -q --detach "$TMP_ROOT/detached-task" dev
install_preflight_fixture "$TMP_ROOT/detached-task"
if (cd "$TMP_ROOT/detached-task" && LEXIRAY_SWIFTFORMAT_TOOL="$FLOW_SWIFTFORMAT_TOOL" \
  ./script/preflight.sh change >"$TMP_ROOT/detached-preflight.log" 2>&1); then
  echo "preflight accepted a detached linked worktree" >&2
  exit 1
fi
rg -F 'detached HEAD is not a supported working state' \
  "$TMP_ROOT/detached-preflight.log" >/dev/null || {
  cat "$TMP_ROOT/detached-preflight.log" >&2
  echo "preflight did not report the detached-worktree cause" >&2
  exit 1
}

echo "GIT_FLOW_PASS: topology, stale-dev rejection, linked-worktree enforcement"

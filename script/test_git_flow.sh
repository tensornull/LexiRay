#!/usr/bin/env bash
set -euo pipefail

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/lexiray-git-flow.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REMOTE="$TMP_ROOT/remote.git"
WORK="$TMP_ROOT/work"
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
git -C "$WORK" switch -qc chore/stale-dev "$stale_dev"
mkdir -p "$WORK/script"
cp "$ROOT_DIR/script/preflight.sh" "$WORK/script/preflight.sh"
chmod +x "$WORK/script/preflight.sh"

if (cd "$WORK" && ./script/preflight.sh change >"$TMP_ROOT/stale-preflight.log" 2>&1); then
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
git -C "$WORK" switch -qc chore/current-dev dev
(cd "$WORK" && ./script/preflight.sh change >/dev/null)

echo "GIT_FLOW_PASS: task->dev squash, dev->main merge commit, main->dev fast-forward, hotfix backflow, stale-dev rejection"

#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: ./script/request_ai_review.sh [PR_NUMBER] [--force-codex]

Requests the manual dual-agent PR review flow:
  1. GitHub Copilot review via gh pr edit --add-reviewer @copilot
  2. Codex review via an @codex review PR comment

If PR_NUMBER is omitted, the script resolves the PR for the current branch.
USAGE
}

pr_number=""
force_codex=0

for arg in "$@"; do
  case "$arg" in
    --force-codex)
      force_codex=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    ''|*[!0-9]*)
      echo "Unknown argument: $arg" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ -n "$pr_number" ]]; then
        echo "Only one PR number may be provided." >&2
        usage >&2
        exit 2
      fi
      pr_number="$arg"
      ;;
  esac
done

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI 'gh' is required." >&2
  exit 1
fi

if [[ -z "$pr_number" ]]; then
  pr_number="$(gh pr view --json number --jq '.number' 2>/dev/null || true)"
fi

if [[ -z "$pr_number" ]]; then
  echo "Could not resolve a pull request for the current branch. Pass PR_NUMBER explicitly." >&2
  exit 1
fi

gh pr view "$pr_number" --json number,title,url --jq '"PR #\(.number): \(.title)\n\(.url)"'

echo "Requesting GitHub Copilot review..."
if ! gh pr edit "$pr_number" --add-reviewer @copilot; then
  cat >&2 <<'EOF'
Failed to request GitHub Copilot review.
Confirm the repository and account have access to GitHub Copilot Code Review.
EOF
  exit 1
fi

existing_codex_comments="$(
  gh pr view "$pr_number" --json comments \
    --jq '[.comments[]?.body | select(. == "@codex review")] | length'
)"

if [[ "$force_codex" -eq 1 || "$existing_codex_comments" -eq 0 ]]; then
  echo "Triggering Codex review..."
  gh pr comment "$pr_number" --body "@codex review"
else
  echo "Existing @codex review trigger comment found; skipping duplicate Codex trigger."
fi

cat <<EOF

Next checks:
  gh pr checks $pr_number --watch
  gh pr view $pr_number --comments
EOF

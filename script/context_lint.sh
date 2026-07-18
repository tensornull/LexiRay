#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FINDINGS="$(mktemp "${TMPDIR:-/tmp}/lexiray-context-lint.XXXXXX")"
trap 'rm -f "$FINDINGS"' EXIT

cd "$ROOT_DIR"

fail() {
  printf 'CONTEXT_LINT_ERROR: %s\n' "$*" >>"$FINDINGS"
}

# Repository-local Markdown links should survive checkout on another machine.
while IFS=: read -r source match; do
  [[ -n "$source" && -n "$match" ]] || continue
  target="${match#*](}"
  target="${target%)}"
  target="${target%%#*}"
  target="${target#<}"
  target="${target%>}"
  target="${target//%20/ }"
  case "$target" in
    ''|http://*|https://*|mailto:*|app://*) continue ;;
  esac
  if [[ "$target" == /* ]]; then
    fail "$source contains a machine-local absolute link: $target"
    continue
  fi
  source_dir="$(dirname "$source")"
  [[ -e "$source_dir/$target" ]] || fail "$source links to missing path: $target"
done < <(rg --hidden -No '\[[^]]+\]\([^)]+\)' --glob '*.md' --glob '!.git/**' . 2>/dev/null || true)

# One canonical skill definition per name. Nested copies otherwise surface as
# duplicate skills to both Codex and adapters.
while IFS=$'\t' read -r name paths; do
  [[ -n "$name" ]] || continue
  count="$(printf '%s\n' "$paths" | tr ',' '\n' | wc -l | tr -d ' ')"
  [[ "$count" -le 1 ]] || fail "duplicate skill name '$name': $paths"
done < <(
  find .agents/skills -name SKILL.md -type f -print 2>/dev/null |
    while IFS= read -r skill_file; do
      skill_name="$(awk '/^name:[[:space:]]*/ {sub(/^[^:]*:[[:space:]]*/, ""); gsub(/\"/, ""); print; exit}' "$skill_file")"
      if [[ -n "$skill_name" ]]; then
        printf '%s\t%s\n' "$skill_name" "$skill_file"
      fi
    done |
    LC_ALL=C sort |
    awk -F '\t' '{ paths[$1] = paths[$1] (paths[$1] ? "," : "") $2 } END { for (name in paths) print name "\t" paths[name] }'
)

while IFS= read -r link; do
  [[ -e "$link" ]] || fail "broken agent symlink: $link -> $(readlink "$link")"
done < <(find .agents .claude -type l -print 2>/dev/null || true)

tracked_codex="$(
  git ls-files '.codex/**' '.codex/*' |
    while IFS= read -r tracked_path; do
      if [[ -e "$tracked_path" || -L "$tracked_path" ]]; then
        printf '%s\n' "$tracked_path"
      fi
    done
)"
[[ -z "$tracked_codex" ]] || fail "generated .codex paths are tracked: $(printf '%s' "$tracked_codex" | paste -sd, -)"

if rg -n -i 'current (release )?dmgs? (are|is).*unsigned|current release builds? (are|is).*unsigned' \
  AGENTS.md README.md CONTRIBUTING.md .github .agents 2>/dev/null >"$FINDINGS.unsigned"; then
  fail "stale unsigned-release guidance: $(head -n 1 "$FINDINGS.unsigned")"
fi
rm -f "$FINDINGS.unsigned"

if rg -n 'install_to_applications|INSTALLED_APP_BUNDLE|rm -rf ["'\"']?/Applications|cp .*[/]Applications' \
  script/build_and_run.sh >/dev/null 2>&1; then
  fail "script/build_and_run.sh must remain workspace-only"
fi

if rg -n 'NSPasteboard\.general' LexiRayTests script/tests >/dev/null 2>&1; then
  fail "automated tests must use isolated named pasteboards, never NSPasteboard.general"
fi

if rg -n 'tccutil[[:space:]]+reset' script .agents/skills >/dev/null 2>&1; then
  fail "automated workflows must not reset TCC"
fi

if rg -n '\.codex/(skills|prompts)' AGENTS.md README.md CONTRIBUTING.md .agents 2>/dev/null >"$FINDINGS.codex-links"; then
  fail "stale .codex compatibility path: $(head -n 1 "$FINDINGS.codex-links")"
fi
rm -f "$FINDINGS.codex-links"

if rg -n -i 'do not replace /Applications.*unless.*explicit|explicitly asks?.*(install|replace)' \
  .agents/skills/lexiray-install-applications 2>/dev/null >"$FINDINGS.install-confirm"; then
  fail "installed-app workflow still requires routine explicit confirmation: $(head -n 1 "$FINDINGS.install-confirm")"
fi
rm -f "$FINDINGS.install-confirm"

if rg -n 'F13/F14|build_and_run\.sh --verify|Target `main` from `dev`' \
  README.md CONTRIBUTING.md .agents 2>/dev/null >"$FINDINGS.stale-workflow"; then
  fail "stale workflow guidance: $(head -n 1 "$FINDINGS.stale-workflow")"
fi
rm -f "$FINDINGS.stale-workflow"

workflow_event_has_branch() {
  local workflow="$1"
  local event="$2"
  local branch="$3"
  /usr/bin/awk -v event="$event" -v branch="$branch" '
    $0 == "  " event ":" { in_event = 1; in_branches = 0; next }
    in_event && /^  [a-zA-Z_]+:/ { in_event = 0; in_branches = 0 }
    in_event && /^    branches:/ { in_branches = 1; next }
    in_event && in_branches && $0 == "      - " branch { found = 1 }
    in_event && in_branches && /^    [a-zA-Z_]+:/ { in_branches = 0 }
    END { exit(found ? 0 : 1) }
  ' "$workflow"
}

for branch in main dev; do
  workflow_event_has_branch .github/workflows/ci.yml push "$branch" ||
    fail ".github/workflows/ci.yml does not run for $branch pushes"
  workflow_event_has_branch .github/workflows/ci.yml pull_request "$branch" ||
    fail ".github/workflows/ci.yml does not run for PRs targeting $branch"
done
rg -F '  workflow_dispatch:' .github/workflows/codeql.yml >/dev/null 2>&1 ||
  fail ".github/workflows/codeql.yml must support manual runs"
rg -F '  schedule:' .github/workflows/codeql.yml >/dev/null 2>&1 ||
  fail ".github/workflows/codeql.yml must run on a schedule"
if rg -n '^  (push|pull_request):' .github/workflows/codeql.yml >/dev/null 2>&1; then
  fail ".github/workflows/codeql.yml must not block pushes or pull requests"
fi
rg -F './script/context_lint.sh' .github/workflows/ci.yml >/dev/null 2>&1 ||
  fail ".github/workflows/ci.yml does not run context lint"
[[ -x script/tests/git_flow_test.sh ]] ||
  fail "script/tests/git_flow_test.sh must register the Git topology contract in unified gates"

if [[ ! -f CLAUDE.md ]]; then
  fail "CLAUDE.md thin adapter is missing"
elif [[ "$(tr -d '\r' <CLAUDE.md | sed '/^[[:space:]]*$/d')" != '@AGENTS.md' ]]; then
  fail "CLAUDE.md must contain only @AGENTS.md"
fi

if [[ ! -L .claude/skills ]]; then
  fail ".claude/skills must be a symlink to ../.agents/skills"
elif [[ "$(readlink .claude/skills)" != '../.agents/skills' ]]; then
  fail ".claude/skills points to $(readlink .claude/skills), expected ../.agents/skills"
fi

if [[ -f AGENTS.md ]]; then
  agents_lines="$(wc -l <AGENTS.md | tr -d ' ')"
  [[ "$agents_lines" -le 140 ]] || fail "AGENTS.md is $agents_lines lines; keep always-on context at or below 140"
fi

for heading in Now Next Backlog; do
  rg -n "^##[[:space:]]+$heading([[:space:]]|$)" ROADMAP.md >/dev/null 2>&1 ||
    fail "ROADMAP.md is missing the '$heading' section"
done

roadmap_ids="$(mktemp "${TMPDIR:-/tmp}/lexiray-roadmap-ids.XXXXXX")"
trap 'rm -f "$FINDINGS" "$roadmap_ids"' EXIT
while IFS= read -r task_line; do
  line_number="${task_line%%:*}"
  task="${task_line#*:}"
  task_id="$(printf '%s\n' "$task" | sed -nE 's/^- \[[ x~]\] \*\*([A-Z][A-Z0-9]*-[0-9]{3})\*\*.*/\1/p')"
  if [[ -z "$task_id" ]]; then
    fail "ROADMAP.md:$line_number has an invalid or missing stable task ID"
  else
    printf '%s\n' "$task_id" >>"$roadmap_ids"
  fi
done < <(rg -n '^- \[' ROADMAP.md || true)
[[ -s "$roadmap_ids" ]] || fail "ROADMAP.md contains no stable task IDs"
duplicate_roadmap_ids="$(LC_ALL=C sort "$roadmap_ids" | uniq -d | paste -sd, -)"
[[ -z "$duplicate_roadmap_ids" ]] || fail "ROADMAP.md contains duplicate task IDs: $duplicate_roadmap_ids"

if [[ -s "$FINDINGS" ]]; then
  cat "$FINDINGS" >&2
  exit 1
fi

echo "CONTEXT_LINT_PASS"

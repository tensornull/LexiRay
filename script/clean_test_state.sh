#!/usr/bin/env bash
# One-time cleanup of UserDefaults domains and temp directories leaked by
# LexiRay unit-test runs before scratch-state teardown was added
# (LexiRayTests/TestScratchState.swift). Safe to rerun; it only touches
# UUID-suffixed test domains and never the real app domain
# (io.github.tensornull.lexiray).
set -euo pipefail

MODE="${1:---dry-run}"
case "$MODE" in
  --dry-run|dry-run) APPLY=0 ;;
  --apply|apply) APPLY=1 ;;
  *)
    echo "usage: $0 [--dry-run|--apply]" >&2
    exit 2
    ;;
esac

PREFIX_RE='(LexiRayTests|LexiRayControllerTests|LexiRayPipelineTests|LexiRaySettingsStoreTests|LexiRayHistoryStoreTests|LexiRayTestScratch)'
UUID_RE='[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}'

PREFS_DIR="$HOME/Library/Preferences"
domains="$( (ls "$PREFS_DIR" 2>/dev/null || true) |
  grep -E "^${PREFIX_RE}-${UUID_RE}\.plist$" |
  sed 's/\.plist$//' || true)"

TMP_PARENT="${TMPDIR:-/tmp}"
scratch_dirs="$(find -E "$TMP_PARENT" -maxdepth 1 -type d \
  -regex ".*/${PREFIX_RE}-${UUID_RE}" -print 2>/dev/null || true)"

domain_count=0
[[ -n "$domains" ]] && domain_count="$(printf '%s\n' "$domains" | wc -l | tr -d ' ')"
dir_count=0
[[ -n "$scratch_dirs" ]] && dir_count="$(printf '%s\n' "$scratch_dirs" | wc -l | tr -d ' ')"

echo "Leaked test defaults domains: $domain_count"
echo "Leaked test temp directories: $dir_count"

if [[ "$domain_count" -eq 0 && "$dir_count" -eq 0 ]]; then
  echo "Nothing to clean."
  exit 0
fi

if [[ "$APPLY" -eq 0 ]]; then
  printf '%s\n' "$domains" | sed -n '1,3p' | sed 's/^/  e.g. /'
  echo "Dry run. Run $0 --apply to delete them."
  exit 0
fi

if [[ -n "$domains" ]]; then
  # defaults(1) keeps cfprefsd coherent; emptied domains still leave a plist
  # file behind, so remove that too. Parallelize because thousands of domains
  # may have accumulated.
  printf '%s\n' "$domains" |
    xargs -P 8 -n 25 sh -c 'for d; do
      defaults delete "$d" >/dev/null 2>&1 || true
      rm -f "$HOME/Library/Preferences/$d.plist"
    done' _
  echo "Deleted $domain_count test defaults domains."
fi

if [[ -n "$scratch_dirs" ]]; then
  printf '%s\n' "$scratch_dirs" | while read -r dir; do
    [[ -n "$dir" ]] || continue
    rm -rf -- "$dir"
  done
  echo "Deleted $dir_count test temp directories."
fi

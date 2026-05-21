#!/usr/bin/env bash
set -euo pipefail

MODE="${1:---dry-run}"
APP_NAME="LexiRay"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CANONICAL_APP="$ROOT_DIR/build/DerivedData/Build/Products/Debug/$APP_NAME.app"

case "$MODE" in
  --dry-run|dry-run) APPLY=0 ;;
  --apply|apply) APPLY=1 ;;
  *)
    echo "usage: $0 [--dry-run|--apply]" >&2
    exit 2
    ;;
esac

candidate_apps() {
  if [[ -d "$ROOT_DIR/build" ]]; then
    find "$ROOT_DIR/build" -name "$APP_NAME.app" -type d -prune -print 2>/dev/null
  fi

  if [[ -d "$HOME/Library/Developer/Xcode/DerivedData" ]]; then
    find "$HOME/Library/Developer/Xcode/DerivedData" \
      -path "*/$APP_NAME-*/Build/Products/*/$APP_NAME.app" \
      -type d \
      -prune \
      -print 2>/dev/null
  fi
}

stale_apps="$(candidate_apps | sort -u | while read -r app; do
  [[ -n "$app" ]] || continue
  [[ "$app" == "$CANONICAL_APP" ]] && continue
  printf '%s\n' "$app"
done)"

if [[ -z "$stale_apps" ]]; then
  echo "No stale LexiRay development app bundles found."
  exit 0
fi

if [[ "$APPLY" -eq 0 ]]; then
  echo "Dry run. Stale LexiRay development app bundles:"
  printf '%s\n' "$stale_apps" | sed 's/^/  /'
  echo "Run $0 --apply to remove only these development bundles."
  exit 0
fi

printf '%s\n' "$stale_apps" | while read -r app; do
  [[ -n "$app" ]] || continue
  rm -rf -- "$app"
  echo "Removed $app"
done

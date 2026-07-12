#!/usr/bin/env bash
set -euo pipefail

echo "Generating a new LexiRay release identity is intentionally disabled." >&2
echo "New identities break upgrade and macOS permission continuity." >&2
echo "Recover the original P12 or use script/release.sh publish for the GitHub fallback." >&2
exit 1

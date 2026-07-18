#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Compatibility entry point. Deliberately ignores the historical display-name
# argument: normal builds must use the repository-pinned fingerprint.
"$ROOT_DIR/script/development_identity.sh" verify >/dev/null

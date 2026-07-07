#!/usr/bin/env bash
# test-skill-bundles.sh - Verify bundled skill helper scripts are in sync.
# Usage: bash scripts/tests/test-skill-bundles.sh

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SYNC_TOOL="$ROOT_DIR/tools/sync-skill-scripts.sh"

OUTPUT="$(bash "$SYNC_TOOL" --check 2>&1)"
CODE=$?

if [[ "$CODE" -eq 0 ]]; then
    printf '%s\n' 'PASS: skill bundled scripts test'
    exit 0
fi

printf '%s\n' 'FAIL: skill bundled scripts test' >&2
printf '%s\n' "$OUTPUT" >&2
exit 1

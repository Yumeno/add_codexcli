#!/usr/bin/env bash
# test-list-models.sh - Tests for list-codex-models.sh
# Usage: bash scripts/tests/test-list-models.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HELPER="$SCRIPT_DIR/scripts/list-codex-models.sh"

PASSED=0
FAILED=0
TOTAL=0

test_case() {
    TOTAL=$((TOTAL + 1))
    printf "  TEST: %s ... " "$1"
}
pass() { echo "PASS"; PASSED=$((PASSED + 1)); }
fail() { echo "FAIL: $1"; FAILED=$((FAILED + 1)); }

echo ""
echo "=== list-codex-models.sh Tests ==="
echo ""

test_case "Rejects unknown options"
OUTPUT=$(bash "$HELPER" --no-such-flag 2>&1)
CODE=$?
if [[ $CODE -eq 1 ]]; then pass; else fail "Expected exit 1, got $CODE"; fi

test_case "Prints help with -h"
OUTPUT=$(bash "$HELPER" -h 2>&1)
CODE=$?
if [[ $CODE -eq 0 ]] && echo "$OUTPUT" | grep -qi "usage"; then
    pass
else
    fail "Expected exit 0 with usage text, got exit=$CODE output='$OUTPUT'"
fi

test_case "Lists at least one model name (default mode)"
OUTPUT=$(bash "$HELPER" 2>&1)
CODE=$?
if [[ $CODE -eq 0 ]] && [[ -n "$OUTPUT" ]]; then
    pass
else
    fail "Expected exit 0 with non-empty output, got exit=$CODE output='$OUTPUT'"
fi

test_case "--json mode emits JSON (starts with { or [)"
OUTPUT=$(bash "$HELPER" --json 2>&1)
CODE=$?
FIRST_CHAR=$(printf '%s' "$OUTPUT" | sed -e 's/^[[:space:]]*//' | cut -c1)
if [[ $CODE -eq 0 ]] && [[ "$FIRST_CHAR" == "{" || "$FIRST_CHAR" == "[" ]]; then
    pass
else
    fail "Expected JSON output, got exit=$CODE first='$FIRST_CHAR' output='$OUTPUT'"
fi

test_case "--bundled mode also produces output"
OUTPUT=$(bash "$HELPER" --bundled 2>&1)
CODE=$?
if [[ $CODE -eq 0 ]] && [[ -n "$OUTPUT" ]]; then
    pass
else
    fail "Expected exit 0 with non-empty output, got exit=$CODE output='$OUTPUT'"
fi

echo ""
echo "=== Results ==="
echo "Passed: $PASSED / $TOTAL"
if [[ $FAILED -gt 0 ]]; then
    echo "Failed: $FAILED"
    exit 1
fi
exit 0

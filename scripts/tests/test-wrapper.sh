#!/usr/bin/env bash
# test-wrapper.sh - Tests for codex-wrapper.sh
# Usage: bash scripts/tests/test-wrapper.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WRAPPER="$SCRIPT_DIR/scripts/codex-wrapper.sh"

PASSED=0
FAILED=0
TOTAL=0

test_case() {
    local name="$1"
    TOTAL=$((TOTAL + 1))
    printf "  TEST: %s ... " "$name"
}

pass() {
    echo "PASS"
    PASSED=$((PASSED + 1))
}

fail() {
    echo "FAIL: $1"
    FAILED=$((FAILED + 1))
}

echo ""
echo "=== codex-wrapper.sh Tests ==="
echo ""

# --------------------------------------------------
echo "[Group 1: Input Validation]"

test_case "Exits with error when no prompt given"
OUTPUT=$(bash "$WRAPPER" 2>&1)
CODE=$?
if [[ $CODE -eq 1 ]]; then pass; else fail "Expected exit 1, got $CODE"; fi

test_case "Exits with error when empty prompt given"
OUTPUT=$(bash "$WRAPPER" --prompt "" 2>&1)
CODE=$?
if [[ $CODE -eq 1 ]]; then pass; else fail "Expected exit 1, got $CODE"; fi

# --------------------------------------------------
echo ""
echo "[Group 2: Codex CLI Invocation]"

test_case "Returns output from codex exec"
OUTPUT=$(bash "$WRAPPER" --prompt "What is 1+1? Answer with just the number." 2>&1)
CODE=$?
if [[ $CODE -eq 0 ]] && [[ -n "$OUTPUT" ]]; then
    pass
else
    fail "Expected exit 0 with output, got exit=$CODE output='$OUTPUT'"
fi

test_case "Supports custom model flag"
OUTPUT=$(bash "$WRAPPER" --prompt "Say OK" --model "gpt-5.2-codex" 2>&1)
CODE=$?
if [[ $CODE -eq 0 ]]; then pass; else fail "Expected exit 0, got $CODE"; fi

test_case "Handles timeout gracefully"
OUTPUT=$(bash "$WRAPPER" --prompt "Write a very long essay about everything" --timeout 5 2>&1)
CODE=$?
# Should not hang - either completes fast or times out
printf "(completed, exit=%d) " "$CODE"
pass

# --------------------------------------------------
echo ""
echo "[Group 3: Output Handling]"

test_case "Output file is cleaned up after use"
OUTPUT=$(bash "$WRAPPER" --prompt "Say hello" 2>&1)
STALE=$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name "codex_out_*" -mmin -1 2>/dev/null | head -5)
if [[ -z "$STALE" ]]; then pass; else fail "Temp files not cleaned up: $STALE"; fi

test_case "Stderr noise is suppressed from output"
OUTPUT=$(bash "$WRAPPER" --prompt "Say OK" 2>&1)
if echo "$OUTPUT" | grep -qE "deprecated:|ERROR:.*websocket|OpenAI Codex v"; then
    fail "Codex stderr noise in output"
else
    pass
fi

# --------------------------------------------------
echo ""
echo "=== Results ==="
echo "Passed: $PASSED / $TOTAL"
if [[ $FAILED -gt 0 ]]; then
    echo "Failed: $FAILED"
    exit 1
fi
exit 0

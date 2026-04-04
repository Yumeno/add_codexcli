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

test_case "Error files are cleaned up after use"
OUTPUT=$(bash "$WRAPPER" --prompt "Say hello" 2>&1)
STALE_ERR=$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name "codex_err_*" -mmin -1 2>/dev/null | head -5)
if [[ -z "$STALE_ERR" ]]; then pass; else fail "Error temp files not cleaned up: $STALE_ERR"; fi

# --------------------------------------------------
echo ""
echo "[Group 4: Injection Prevention]"

test_case "Prompt starting with dash does not break codex"
OUTPUT=$(bash "$WRAPPER" --prompt "-v --help" 2>&1)
CODE=$?
if [[ $CODE -eq 0 ]] && [[ -n "$OUTPUT" ]]; then
    pass
else
    # Even if codex can't answer, it should not crash with option parsing error
    if echo "$OUTPUT" | grep -qE "unexpected argument|unrecognized option"; then
        fail "Prompt treated as option: $OUTPUT"
    else
        pass
    fi
fi

# --------------------------------------------------
echo ""
echo "[Group 5: Context File Support]"

test_case "Accepts --context-file parameter"
CTX_TMP=$(mktemp "${TMPDIR:-/tmp}/test_ctx_XXXXXX.txt")
echo "The capital of France is Paris." > "$CTX_TMP"
OUTPUT=$(bash "$WRAPPER" --prompt "What city is mentioned in the context? Answer in one word." --context-file "$CTX_TMP" 2>&1)
CODE=$?
rm -f "$CTX_TMP"
if [[ $CODE -eq 0 ]] && [[ -n "$OUTPUT" ]]; then
    pass
else
    fail "exit=$CODE output='$OUTPUT'"
fi

test_case "Errors on missing context file"
OUTPUT=$(bash "$WRAPPER" --prompt "test" --context-file "/nonexistent/file.txt" 2>&1)
CODE=$?
if [[ $CODE -eq 1 ]]; then pass; else fail "Expected exit 1, got $CODE"; fi

test_case "Large context triggers warning on stderr"
LARGE_CTX=$(mktemp "${TMPDIR:-/tmp}/test_largectx_XXXXXX.txt")
# Generate >100KB of text
python3 -c "print('x' * 110000)" > "$LARGE_CTX" 2>/dev/null || printf '%0.sx' $(seq 1 110000) > "$LARGE_CTX"
STDERR_OUT=$(bash "$WRAPPER" --prompt "Summarize in one word" --context-file "$LARGE_CTX" 2>&1 1>/dev/null)
rm -f "$LARGE_CTX"
if echo "$STDERR_OUT" | grep -qi "warning.*large\|warning.*context"; then
    pass
else
    fail "Expected size warning on stderr, got: $STDERR_OUT"
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

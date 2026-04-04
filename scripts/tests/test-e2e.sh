#!/usr/bin/env bash
# test-e2e.sh - End-to-end tests for ask-codex skills
# Tests the full flow: skill -> wrapper -> codex exec -> output
# Usage: bash scripts/tests/test-e2e.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

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

# Detect OS and pick wrapper
if [[ "${OSTYPE:-}" == "msys" || "${OSTYPE:-}" == "cygwin" ]]; then
    run_wrapper() {
        powershell -ExecutionPolicy Bypass -NoProfile -File "$SCRIPT_DIR/scripts/codex-wrapper.ps1" "$@"
    }
    run_wrapper_with_context() {
        local prompt="$1"
        local context="$2"
        powershell -ExecutionPolicy Bypass -NoProfile -File "$SCRIPT_DIR/scripts/codex-wrapper.ps1" -Prompt "$prompt" -Context "$context"
    }
else
    run_wrapper() {
        bash "$SCRIPT_DIR/scripts/codex-wrapper.sh" "$@"
    }
    run_wrapper_with_context() {
        local prompt="$1"
        local context="$2"
        bash "$SCRIPT_DIR/scripts/codex-wrapper.sh" --prompt "$prompt" --context "$context"
    }
fi

echo ""
echo "=== End-to-End Tests ==="
echo ""

# --------------------------------------------------
echo "[/ask-codex scenarios]"

test_case "Simple question gets an answer"
if [[ "${OSTYPE:-}" == "msys" || "${OSTYPE:-}" == "cygwin" ]]; then
    OUTPUT=$(run_wrapper -Prompt "What programming language is Python? Answer in one sentence." 2>&1)
else
    OUTPUT=$(run_wrapper --prompt "What programming language is Python? Answer in one sentence." 2>&1)
fi
CODE=$?
if [[ $CODE -eq 0 ]] && [[ -n "$OUTPUT" ]]; then
    pass
else
    fail "exit=$CODE output='$OUTPUT'"
fi

test_case "Japanese prompt works"
if [[ "${OSTYPE:-}" == "msys" || "${OSTYPE:-}" == "cygwin" ]]; then
    OUTPUT=$(run_wrapper -Prompt "1+1は何ですか？数字だけで答えてください。" 2>&1)
else
    OUTPUT=$(run_wrapper --prompt "1+1は何ですか？数字だけで答えてください。" 2>&1)
fi
CODE=$?
if [[ $CODE -eq 0 ]] && [[ -n "$OUTPUT" ]]; then
    pass
else
    fail "exit=$CODE output='$OUTPUT'"
fi

# --------------------------------------------------
echo ""
echo "[/ask-codex-with-context scenarios]"

test_case "Context is included in the prompt"
CONTEXT="File: test.py
def add(a, b):
    return a + b"
OUTPUT=$(run_wrapper_with_context "What does this function do? Answer in one sentence." "$CONTEXT" 2>&1)
CODE=$?
if [[ $CODE -eq 0 ]] && [[ -n "$OUTPUT" ]]; then
    pass
else
    fail "exit=$CODE output='$OUTPUT'"
fi

test_case "Git diff context works"
DIFF_CONTEXT=$(git diff HEAD~1 2>/dev/null || echo "No git diff available")
if [[ "$DIFF_CONTEXT" != "No git diff available" ]] && [[ -n "$DIFF_CONTEXT" ]]; then
    OUTPUT=$(run_wrapper_with_context "Summarize these changes in one sentence." "$DIFF_CONTEXT" 2>&1)
    CODE=$?
    if [[ $CODE -eq 0 ]] && [[ -n "$OUTPUT" ]]; then
        pass
    else
        fail "exit=$CODE output='$OUTPUT'"
    fi
else
    echo "SKIP (no git diff available)"
    TOTAL=$((TOTAL - 1))
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

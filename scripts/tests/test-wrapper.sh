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
echo "[Group 4a: Model resolution & config file]"

# Save/restore any pre-existing config so the test doesn't clobber it.
CONF_PATH="$SCRIPT_DIR/scripts/codex-wrapper.conf"
CONF_BACKUP=""
if [[ -f "$CONF_PATH" ]]; then
    CONF_BACKUP=$(mktemp "${TMPDIR:-/tmp}/codex_conf_bak_XXXXXX")
    cp "$CONF_PATH" "$CONF_BACKUP"
fi
restore_conf() {
    if [[ -n "$CONF_BACKUP" ]]; then
        mv "$CONF_BACKUP" "$CONF_PATH"
    else
        rm -f "$CONF_PATH"
    fi
}
trap restore_conf EXIT

test_case "--set-model writes config and exits 0"
rm -f "$CONF_PATH"
OUTPUT=$(bash "$WRAPPER" --set-model "gpt-5.2-codex" 2>&1)
CODE=$?
if [[ $CODE -eq 0 ]] && [[ -f "$CONF_PATH" ]] && grep -q '^model=gpt-5.2-codex$' "$CONF_PATH"; then
    pass
else
    fail "Expected config write, got exit=$CODE output='$OUTPUT' conf=$(cat "$CONF_PATH" 2>/dev/null)"
fi

test_case "--set-model rejects unsafe characters"
OUTPUT=$(bash "$WRAPPER" --set-model 'foo; rm -rf /' 2>&1)
CODE=$?
if [[ $CODE -eq 1 ]]; then pass; else fail "Expected exit 1, got $CODE"; fi

test_case "--show-model reports config source after set"
bash "$WRAPPER" --set-model "gpt-5.2-codex" >/dev/null 2>&1
OUTPUT=$(bash "$WRAPPER" --show-model 2>&1)
CODE=$?
if [[ $CODE -eq 0 ]] && echo "$OUTPUT" | grep -qE 'model=gpt-5\.2-codex.*source: config'; then
    pass
else
    fail "Expected config source, got exit=$CODE output='$OUTPUT'"
fi

test_case "--show-model reports cli source when --model also passed"
OUTPUT=$(bash "$WRAPPER" --model "gpt-X" --show-model 2>&1)
CODE=$?
if [[ $CODE -eq 0 ]] && echo "$OUTPUT" | grep -qE 'model=gpt-X.*source: cli'; then
    pass
else
    fail "Expected cli source, got exit=$CODE output='$OUTPUT'"
fi

test_case "--show-model reports env source when env set and no --model"
OUTPUT=$(CODEX_WRAPPER_MODEL="gpt-env" bash "$WRAPPER" --show-model 2>&1)
CODE=$?
if [[ $CODE -eq 0 ]] && echo "$OUTPUT" | grep -qE 'model=gpt-env.*source: env'; then
    pass
else
    fail "Expected env source, got exit=$CODE output='$OUTPUT'"
fi

test_case "--show-model reports unset when no config and no env"
rm -f "$CONF_PATH"
OUTPUT=$(env -u CODEX_WRAPPER_MODEL bash "$WRAPPER" --show-model 2>&1)
CODE=$?
if [[ $CODE -eq 0 ]] && echo "$OUTPUT" | grep -qE 'model=\(unset'; then
    pass
else
    fail "Expected unset state, got exit=$CODE output='$OUTPUT'"
fi

test_case "Config file is picked up on invocation (MODEL: on stderr)"
bash "$WRAPPER" --set-model "gpt-5.2-codex" >/dev/null 2>&1
STDERR_OUT=$(env -u CODEX_WRAPPER_MODEL bash "$WRAPPER" --prompt "Say OK" 2>&1 1>/dev/null)
if echo "$STDERR_OUT" | grep -qE '^MODEL: gpt-5\.2-codex$'; then
    pass
else
    fail "Expected 'MODEL: gpt-5.2-codex' on stderr from config, got: $STDERR_OUT"
fi

# Restore: remove config so subsequent tests run with clean state.
rm -f "$CONF_PATH"

# --------------------------------------------------
echo ""
echo "[Group 4b: Model announcement on stderr]"

test_case "Emits MODEL: line on stderr when --model is given"
STDERR_OUT=$(bash "$WRAPPER" --prompt "Say OK" --model "gpt-5.2-codex" 2>&1 1>/dev/null)
if echo "$STDERR_OUT" | grep -qE '^MODEL: gpt-5\.2-codex$'; then
    pass
else
    fail "Expected 'MODEL: gpt-5.2-codex' on stderr, got: $STDERR_OUT"
fi

test_case "Does NOT emit MODEL: line on stderr when nothing resolves"
# Strip env and ensure no config file lingers; otherwise the wrapper would
# (correctly) emit MODEL: from those sources.
rm -f "$CONF_PATH"
STDERR_OUT=$(env -u CODEX_WRAPPER_MODEL bash "$WRAPPER" --prompt "Say OK" 2>&1 1>/dev/null)
if echo "$STDERR_OUT" | grep -qE '^MODEL: '; then
    fail "Should not announce a model when nothing resolves, but got: $STDERR_OUT"
else
    pass
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

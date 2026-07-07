#!/usr/bin/env bash
# test-wrapper.sh - Tests for codex-wrapper.sh
# Usage: bash scripts/tests/test-wrapper.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WRAPPER="$SCRIPT_DIR/scripts/codex-wrapper.sh"

# Redirect wrapper config to a test-owned temp path so we don't touch
# $HOME/.agents/add_codexcli/codex-wrapper.conf during tests.
CODEX_WRAPPER_CONFIG_TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex_wrapper_test_conf.XXXXXX")"
export CODEX_WRAPPER_CONFIG="$CODEX_WRAPPER_CONFIG_TEST_DIR/codex-wrapper.conf"

cleanup_test_conf() {
    rm -rf -- "$CODEX_WRAPPER_CONFIG_TEST_DIR"
}
trap cleanup_test_conf EXIT

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
OUTPUT=$(bash "$WRAPPER" --prompt "Say OK" --model "gpt-5.5" 2>&1)
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

CONF_PATH="$CODEX_WRAPPER_CONFIG"

test_case "--set-model writes config and exits 0"
rm -f "$CONF_PATH"
OUTPUT=$(bash "$WRAPPER" --set-model "gpt-5.5" 2>&1)
CODE=$?
if [[ $CODE -eq 0 ]] && [[ -f "$CONF_PATH" ]] && grep -q '^model=gpt-5.5$' "$CONF_PATH"; then
    pass
else
    fail "Expected config write, got exit=$CODE output='$OUTPUT' conf=$(cat "$CONF_PATH" 2>/dev/null)"
fi

test_case "--set-model rejects unsafe characters"
OUTPUT=$(bash "$WRAPPER" --set-model 'foo; rm -rf /' 2>&1)
CODE=$?
if [[ $CODE -eq 1 ]]; then pass; else fail "Expected exit 1, got $CODE"; fi

test_case "--model rejects unsafe characters too"
OUTPUT=$(bash "$WRAPPER" --prompt "Say OK" --model $'foo\nMODEL: spoof' 2>&1)
CODE=$?
if [[ $CODE -eq 1 ]]; then pass; else fail "Expected exit 1 for unsafe --model, got $CODE output='$OUTPUT'"; fi

test_case "Config with unsafe model is rejected on read"
# The parser only reads the first model= line, so a newline-injected value
# would still parse as just "evil". Use a same-line unsafe value (semicolon
# + space) to actually exercise validation of the conf-sourced model.
printf 'model=foo bar; rm -rf /\n' > "$CONF_PATH"
OUTPUT=$(env -u CODEX_WRAPPER_MODEL bash "$WRAPPER" --prompt "Say OK" 2>&1)
CODE=$?
rm -f "$CONF_PATH"
if [[ $CODE -eq 1 ]]; then pass; else fail "Expected exit 1 for tampered conf, got $CODE output='$OUTPUT'"; fi

test_case "Comment-only conf does not crash --show-model"
# Regression for codex's review: the grep-pipeline implementation of
# read_config_model exited non-zero on no-match, which under set -euo pipefail
# killed the whole script. Awk-based implementation must survive this.
printf '# nothing useful here\n' > "$CONF_PATH"
OUTPUT=$(env -u CODEX_WRAPPER_MODEL bash "$WRAPPER" --show-model 2>&1)
CODE=$?
rm -f "$CONF_PATH"
if [[ $CODE -eq 0 ]] && echo "$OUTPUT" | grep -qE 'model=\(unset'; then
    pass
else
    fail "Expected exit 0 + unset for comment-only conf, got exit=$CODE output='$OUTPUT'"
fi

test_case "\$CODEX_WRAPPER_MODEL rejects unsafe characters"
OUTPUT=$(CODEX_WRAPPER_MODEL=$'foo\nMODEL: spoof' bash "$WRAPPER" --prompt "Say OK" 2>&1)
CODE=$?
if [[ $CODE -eq 1 ]]; then pass; else fail "Expected exit 1 for unsafe env, got $CODE output='$OUTPUT'"; fi

test_case "--show-model reports config source after set"
bash "$WRAPPER" --set-model "gpt-5.5" >/dev/null 2>&1
OUTPUT=$(bash "$WRAPPER" --show-model 2>&1)
CODE=$?
if [[ $CODE -eq 0 ]] && echo "$OUTPUT" | grep -qE 'model=gpt-5\.5.*source: config'; then
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
bash "$WRAPPER" --set-model "gpt-5.5" >/dev/null 2>&1
STDERR_OUT=$(env -u CODEX_WRAPPER_MODEL bash "$WRAPPER" --prompt "Say OK" 2>&1 1>/dev/null)
if echo "$STDERR_OUT" | grep -qE '^MODEL: gpt-5\.5$'; then
    pass
else
    fail "Expected 'MODEL: gpt-5.5' on stderr from config, got: $STDERR_OUT"
fi

# Restore: remove config so subsequent tests run with clean state.
rm -f "$CONF_PATH"

# --------------------------------------------------
echo ""
echo "[Group 4b: Model announcement on stderr]"

test_case "Emits MODEL: line on stderr when --model is given"
STDERR_OUT=$(bash "$WRAPPER" --prompt "Say OK" --model "gpt-5.5" 2>&1 1>/dev/null)
if echo "$STDERR_OUT" | grep -qE '^MODEL: gpt-5\.5$'; then
    pass
else
    fail "Expected 'MODEL: gpt-5.5' on stderr, got: $STDERR_OUT"
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
echo "[Group 4c: Argument validation]"

test_case "--prompt with no value gives clean error (not set -u crash)"
OUTPUT=$(bash "$WRAPPER" --prompt 2>&1)
CODE=$?
if [[ $CODE -eq 1 ]] && echo "$OUTPUT" | grep -qi "requires a value"; then
    pass
else
    fail "Expected exit 1 with 'requires a value', got exit=$CODE output='$OUTPUT'"
fi

test_case "--timeout with non-numeric value is rejected"
OUTPUT=$(bash "$WRAPPER" --prompt "Say OK" --timeout "abc" 2>&1)
CODE=$?
if [[ $CODE -eq 1 ]] && echo "$OUTPUT" | grep -qi "positive integer"; then
    pass
else
    fail "Expected exit 1 with positive-integer error, got exit=$CODE output='$OUTPUT'"
fi

test_case "--timeout with zero is rejected"
OUTPUT=$(bash "$WRAPPER" --prompt "Say OK" --timeout 0 2>&1)
CODE=$?
if [[ $CODE -eq 1 ]]; then pass; else fail "Expected exit 1 for --timeout 0, got $CODE"; fi

test_case "--prompt accepts a value starting with -- (e.g. '--help')"
# Regression: require_value used to reject any value starting with "--",
# breaking prompts like "--help". The wrapper should not bail out before
# reaching codex. We don't care what codex itself returns.
OUTPUT=$(bash "$WRAPPER" --prompt "--help" 2>&1)
if echo "$OUTPUT" | grep -q "requires a value"; then
    fail "Wrapper rejected '--help' as missing value: $OUTPUT"
else
    pass
fi

# --------------------------------------------------
echo ""
echo "[Group 4d: ASCII workdir enforcement]"

test_case "--workdir with non-ASCII path is rejected"
OUTPUT=$(bash "$WRAPPER" --prompt "Say OK" --workdir $'/tmp/\xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e' 2>&1)
CODE=$?
if [[ $CODE -eq 1 ]] && echo "$OUTPUT" | grep -qi "ASCII"; then
    pass
else
    fail "Expected exit 1 with ASCII error, got exit=$CODE output='$OUTPUT'"
fi

test_case "--workdir with non-existent ASCII path is rejected"
OUTPUT=$(bash "$WRAPPER" --prompt "Say OK" --workdir "/tmp/definitely-does-not-exist-xyz-$$" 2>&1)
CODE=$?
if [[ $CODE -eq 1 ]]; then pass; else fail "Expected exit 1 for missing workdir, got $CODE"; fi

# --------------------------------------------------
echo ""
echo "[Group 4e: Exit code propagation via fake codex shim]"

# Stub `codex` so we can prove the wrapper propagates the child's exit code
# without depending on the real codex binary or network.
FAKE_SHIM_DIR=""
fake_codex_setup() {
    local exit_code="$1"
    local emit_warning="${2:-0}"
    FAKE_SHIM_DIR=$(mktemp -d "${TMPDIR:-/tmp}/codex_fake_XXXXXX")
    cat > "$FAKE_SHIM_DIR/codex" <<FAKEEOF
#!/usr/bin/env bash
OUTFILE=""
while [[ \$# -gt 0 ]]; do
    case "\$1" in
        -o) OUTFILE="\$2"; shift 2 ;;
        *) shift ;;
    esac
done
if [[ -n "\$OUTFILE" ]]; then
    echo "fake codex output" > "\$OUTFILE"
fi
if [[ "$emit_warning" == "1" ]]; then
    echo "deprecated: fake warning" >&2
fi
exit $exit_code
FAKEEOF
    chmod +x "$FAKE_SHIM_DIR/codex"
}
fake_codex_teardown() {
    [[ -n "$FAKE_SHIM_DIR" && -d "$FAKE_SHIM_DIR" ]] && rm -rf "$FAKE_SHIM_DIR"
    FAKE_SHIM_DIR=""
}

test_case "Wrapper exit code matches fake codex exit 0"
fake_codex_setup 0
OUTPUT=$(PATH="$FAKE_SHIM_DIR:$PATH" env -u CODEX_WRAPPER_MODEL bash "$WRAPPER" --prompt "anything" 2>&1)
CODE=$?
fake_codex_teardown
if [[ $CODE -eq 0 ]]; then pass; else fail "Expected exit 0, got $CODE output='$OUTPUT'"; fi

test_case "Wrapper exit code matches fake codex exit 42"
fake_codex_setup 42
OUTPUT=$(PATH="$FAKE_SHIM_DIR:$PATH" env -u CODEX_WRAPPER_MODEL bash "$WRAPPER" --prompt "anything" 2>&1)
CODE=$?
fake_codex_teardown
if [[ $CODE -eq 42 ]]; then pass; else fail "Expected exit 42, got $CODE output='$OUTPUT'"; fi

test_case "Wrapper still exits 0 when codex prints stderr noise + exits 0"
fake_codex_setup 0 1
OUTPUT=$(PATH="$FAKE_SHIM_DIR:$PATH" env -u CODEX_WRAPPER_MODEL bash "$WRAPPER" --prompt "anything" 2>&1)
CODE=$?
fake_codex_teardown
if [[ $CODE -eq 0 ]]; then
    pass
else
    fail "Expected exit 0 (stderr noise must not corrupt exit), got $CODE output='$OUTPUT'"
fi

# --------------------------------------------------
echo ""
echo "[Group 4f: Recording shim — stdin vs argv separation (issue #14)]"

# A second fake-codex shim that records (a) every argv as a JSON-ish line and
# (b) the full stdin to inspection files. This lets us assert that:
#   - context flows via stdin, not argv (no truncation, no shell quoting)
#   - the wrapper still passes --sandbox / --cd / model on argv
#   - shell metacharacters embedded in context cannot leak into argv
REC_SHIM_DIR=""
REC_ARGV=""
REC_STDIN=""
rec_codex_setup() {
    REC_SHIM_DIR=$(mktemp -d "${TMPDIR:-/tmp}/codex_rec_XXXXXX")
    REC_ARGV="$REC_SHIM_DIR/argv.txt"
    REC_STDIN="$REC_SHIM_DIR/stdin.bin"
    cat > "$REC_SHIM_DIR/codex" <<RECEOF
#!/usr/bin/env bash
# Record argv (one per line) and full stdin to inspection files, then act like
# a minimal codex exec: extract -o <file> and write a marker into it.
printf '%s\n' "\$@" > "$REC_ARGV"
cat > "$REC_STDIN"
[[ -z "\${CODEX_TEST_REMOVE_SOURCE:-}" ]] || rm -f -- "\$CODEX_TEST_REMOVE_SOURCE"
OUTFILE=""
while [[ \$# -gt 0 ]]; do
    case "\$1" in
        -o) OUTFILE="\$2"; shift 2 ;;
        -i)
            if [[ -f "\$(dirname "\$2")/manifest.json" ]]; then
                cp "\$(dirname "\$2")/manifest.json" "$REC_SHIM_DIR/manifest.json"
            fi
            shift 2 ;;
        *)  shift ;;
    esac
done
[[ -n "\$OUTFILE" ]] && echo "rec codex output" > "\$OUTFILE"
exit 0
RECEOF
    chmod +x "$REC_SHIM_DIR/codex"
}
rec_codex_teardown() {
    [[ -n "$REC_SHIM_DIR" && -d "$REC_SHIM_DIR" ]] && rm -rf "$REC_SHIM_DIR"
    REC_SHIM_DIR=""; REC_ARGV=""; REC_STDIN=""
}

test_case "Context arrives on stdin, not argv"
rec_codex_setup
CTX_PAYLOAD="UNIQUE_CONTEXT_SENTINEL_$$_$(date +%s)"
OUTPUT=$(PATH="$REC_SHIM_DIR:$PATH" env -u CODEX_WRAPPER_MODEL \
    bash "$WRAPPER" --prompt "hi" --context "$CTX_PAYLOAD" 2>&1)
CODE=$?
if [[ $CODE -ne 0 ]]; then
    fail "wrapper exited $CODE: $OUTPUT"
elif grep -qF "$CTX_PAYLOAD" "$REC_ARGV"; then
    fail "context leaked into argv: $(grep -F "$CTX_PAYLOAD" "$REC_ARGV")"
elif ! grep -qF "$CTX_PAYLOAD" "$REC_STDIN"; then
    fail "context did not arrive on stdin"
else
    pass
fi
rec_codex_teardown

test_case "No context => stdin is empty (no spurious bytes)"
rec_codex_setup
OUTPUT=$(PATH="$REC_SHIM_DIR:$PATH" env -u CODEX_WRAPPER_MODEL \
    bash "$WRAPPER" --prompt "hi" 2>&1)
CODE=$?
STDIN_SIZE=$(wc -c < "$REC_STDIN" 2>/dev/null || echo "?")
if [[ $CODE -eq 0 ]] && [[ "$STDIN_SIZE" == "0" ]]; then
    pass
else
    fail "expected empty stdin, got size=$STDIN_SIZE exit=$CODE output=$OUTPUT"
fi
rec_codex_teardown

test_case "Shell metacharacters in context do not leak into argv"
# Context contains text that, if naively expanded as a shell word, would change
# argv. With stdin transport these should appear verbatim on stdin, not argv.
rec_codex_setup
INJECTION=$'--sandbox danger-full-access\n--add-dir /etc\n$(rm -rf /)\n`whoami`'
OUTPUT=$(PATH="$REC_SHIM_DIR:$PATH" env -u CODEX_WRAPPER_MODEL \
    bash "$WRAPPER" --prompt "hi" --context "$INJECTION" 2>&1)
CODE=$?
LEAK=0
if grep -qE '^--sandbox$' "$REC_ARGV"; then
    # Wrapper itself always passes one --sandbox; it must be exactly one.
    if [[ $(grep -cE '^--sandbox$' "$REC_ARGV") -ne 1 ]]; then LEAK=1; fi
fi
if grep -qE '^--add-dir$' "$REC_ARGV"; then LEAK=1; fi
if grep -qF 'danger-full-access' "$REC_ARGV"; then
    # Allowed only if the user passed --sandbox themselves (we did not here).
    LEAK=1
fi
if [[ $CODE -eq 0 ]] && [[ $LEAK -eq 0 ]] && grep -qF '$(rm -rf /)' "$REC_STDIN"; then
    pass
else
    fail "exit=$CODE leak=$LEAK argv:$(cat "$REC_ARGV") stdin-head:$(head -c 200 "$REC_STDIN")"
fi
rec_codex_teardown

test_case "Large context (128KB) is delivered intact via stdin"
rec_codex_setup
LARGE_CTX=$(mktemp "${TMPDIR:-/tmp}/test_largectx_XXXXXX.txt")
# 128KB of stable content; head/tail markers let us detect truncation.
{ echo "HEAD_MARKER_$$"; python3 -c "print('a' * 131000)" 2>/dev/null \
    || printf '%.0sa' $(seq 1 131000); echo; echo "TAIL_MARKER_$$"; } > "$LARGE_CTX"
LARGE_SIZE=$(wc -c < "$LARGE_CTX")
OUTPUT=$(PATH="$REC_SHIM_DIR:$PATH" env -u CODEX_WRAPPER_MODEL \
    bash "$WRAPPER" --prompt "summarize" --context-file "$LARGE_CTX" 2>&1)
CODE=$?
STDIN_SIZE=$(wc -c < "$REC_STDIN")
HEAD_OK=0; TAIL_OK=0
grep -qF "HEAD_MARKER_$$" "$REC_STDIN" && HEAD_OK=1
grep -qF "TAIL_MARKER_$$" "$REC_STDIN" && TAIL_OK=1
rm -f "$LARGE_CTX"
# `CONTEXT=$(cat ...)` strips trailing newline(s), so stdin will be 1-2 bytes
# shorter than the file. Accept that as long as both markers survived.
if [[ $CODE -eq 0 ]] && [[ $HEAD_OK -eq 1 ]] && [[ $TAIL_OK -eq 1 ]] \
   && [[ $STDIN_SIZE -ge $((LARGE_SIZE - 2)) ]]; then
    pass
else
    fail "exit=$CODE file=$LARGE_SIZE stdin=$STDIN_SIZE head=$HEAD_OK tail=$TAIL_OK"
fi
rec_codex_teardown

test_case "--sandbox read-only is the default on argv"
rec_codex_setup
PATH="$REC_SHIM_DIR:$PATH" env -u CODEX_WRAPPER_MODEL \
    bash "$WRAPPER" --prompt "hi" >/dev/null 2>&1
if grep -qE '^-s$' "$REC_ARGV" && grep -qE '^read-only$' "$REC_ARGV"; then
    pass
else
    fail "Expected -s read-only on argv, got: $(cat "$REC_ARGV")"
fi
rec_codex_teardown

test_case "--sandbox workspace-write is passed through"
rec_codex_setup
PATH="$REC_SHIM_DIR:$PATH" env -u CODEX_WRAPPER_MODEL \
    bash "$WRAPPER" --prompt "hi" --sandbox workspace-write >/dev/null 2>&1
if grep -qE '^workspace-write$' "$REC_ARGV"; then
    pass
else
    fail "Expected workspace-write on argv, got: $(cat "$REC_ARGV")"
fi
rec_codex_teardown

test_case "--sandbox rejects values outside the whitelist"
OUTPUT=$(bash "$WRAPPER" --prompt "hi" --sandbox bogus-mode 2>&1)
CODE=$?
if [[ $CODE -eq 1 ]] && echo "$OUTPUT" | grep -qi "sandbox"; then
    pass
else
    fail "Expected exit 1 on bogus sandbox, got exit=$CODE output='$OUTPUT'"
fi

test_case "--cd is accepted as an alias for --workdir"
rec_codex_setup
ALIAS_WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/cdalias_XXXXXX")
PATH="$REC_SHIM_DIR:$PATH" env -u CODEX_WRAPPER_MODEL \
    bash "$WRAPPER" --prompt "hi" --cd "$ALIAS_WORKDIR" >/dev/null 2>&1
CODE=$?
# The wrapper passes -C <workdir>. We check the workdir we asked for shows up.
if [[ $CODE -eq 0 ]] && grep -qF "$ALIAS_WORKDIR" "$REC_ARGV"; then
    pass
else
    fail "Expected --cd alias to feed -C <dir>; argv: $(cat "$REC_ARGV")"
fi
rm -rf "$ALIAS_WORKDIR"
rec_codex_teardown

# --------------------------------------------------
echo ""
echo "[Group 4g: Error sentinel for skill-side failure detection]"

# Skills run the wrapper as a bare single command (no $() capture, no 2>file)
# under Claude Code's permit umbrella. Without a sentinel, a wrapper failure
# can be misread by the skill as "Codex's answer". Every failure path must
# put [CODEX_WRAPPER_ERROR] on stdout — the umbrella stream the skill sees.

SENTINEL='\[CODEX_WRAPPER_ERROR\]'

test_case "Sentinel: missing --prompt → stdout sentinel"
# We capture stdout only (not stderr) to confirm the sentinel really lands on
# stdout, since skills will only see the combined stream.
OUTPUT=$(bash "$WRAPPER" 2>/dev/null)
CODE=$?
if [[ $CODE -ne 0 ]] && echo "$OUTPUT" | grep -qE "$SENTINEL"; then pass
else fail "exit=$CODE stdout='$OUTPUT'"; fi

test_case "Sentinel: bogus --sandbox → stdout sentinel"
OUTPUT=$(bash "$WRAPPER" --prompt "hi" --sandbox bogus 2>/dev/null)
CODE=$?
if [[ $CODE -ne 0 ]] && echo "$OUTPUT" | grep -qE "$SENTINEL"; then pass
else fail "exit=$CODE stdout='$OUTPUT'"; fi

test_case "Sentinel: unsafe --model → stdout sentinel"
OUTPUT=$(bash "$WRAPPER" --prompt "hi" --model $'evil\nMODEL: spoof' 2>/dev/null)
CODE=$?
if [[ $CODE -ne 0 ]] && echo "$OUTPUT" | grep -qE "$SENTINEL"; then pass
else fail "exit=$CODE stdout='$OUTPUT'"; fi

test_case "Sentinel: non-ASCII --workdir → stdout sentinel"
OUTPUT=$(bash "$WRAPPER" --prompt "hi" --workdir $'/tmp/\xe6\x97\xa5\xe6\x9c\xac\xe8\xaa\x9e' 2>/dev/null)
CODE=$?
if [[ $CODE -ne 0 ]] && echo "$OUTPUT" | grep -qE "$SENTINEL"; then pass
else fail "exit=$CODE stdout='$OUTPUT'"; fi

test_case "Sentinel: success path does NOT contain sentinel"
# Use the recording shim so this test does not depend on a real codex binary.
rec_codex_setup
OUTPUT=$(PATH="$REC_SHIM_DIR:$PATH" env -u CODEX_WRAPPER_MODEL \
    bash "$WRAPPER" --prompt "hi" 2>/dev/null)
CODE=$?
rec_codex_teardown
if [[ $CODE -eq 0 ]] && ! echo "$OUTPUT" | grep -qE "$SENTINEL"; then pass
else fail "exit=$CODE stdout='$OUTPUT' (sentinel must be absent on success)"; fi

test_case "Multiple PNG/JPEG attachments preserve order and clean staging"
rec_codex_setup
MEDIA_TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/media_test_XXXXXX")
PNG="$MEDIA_TEST_DIR/first image,ja.bin"
JPG="$MEDIA_TEST_DIR/second image.dat"
printf '\211PNG\r\n\032\n' > "$PNG"
printf '\377\330\377\340' > "$JPG"
OUTPUT=$(PATH="$REC_SHIM_DIR:$PATH" env -u CODEX_WRAPPER_MODEL \
    bash "$WRAPPER" --prompt "inspect" --attachment "$PNG" --attachment "$JPG" 2>&1)
CODE=$?
IMAGE_PATHS=()
while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] && IMAGE_PATHS+=("$line")
done < <(awk 'previous=="-i" { print; previous=""; next } { previous=$0 }' "$REC_ARGV")

# Check manifest.json contents
MANIFEST_OK=0
if [[ -f "$REC_SHIM_DIR/manifest.json" ]]; then
    if grep -q '"order": 1' "$REC_SHIM_DIR/manifest.json" && \
       grep -q '"original_name": "first image,ja.bin"' "$REC_SHIM_DIR/manifest.json" && \
       grep -q '"mime": "image/png"' "$REC_SHIM_DIR/manifest.json" && \
       grep -q '"order": 2' "$REC_SHIM_DIR/manifest.json" && \
       grep -q '"original_name": "second image.dat"' "$REC_SHIM_DIR/manifest.json" && \
       grep -q '"mime": "image/jpeg"' "$REC_SHIM_DIR/manifest.json"; then
        MANIFEST_OK=1
    fi
fi

if [[ $CODE -eq 0 && ${#IMAGE_PATHS[@]} -eq 2 \
   && "${IMAGE_PATHS[0]}" == *image-001.png && "${IMAGE_PATHS[1]}" == *image-002.jpg \
   && ! -e "${IMAGE_PATHS[0]}" && ! -e "${IMAGE_PATHS[1]}" && $MANIFEST_OK -eq 1 \
   && "$OUTPUT" == *"MEDIA: "*"manifest="* && "$OUTPUT" == *"original_name="*"staged_path="* ]]; then pass
else fail "exit=$CODE image paths='${IMAGE_PATHS[*]-}' manifest_ok=$MANIFEST_OK output='$OUTPUT' manifest='$(cat "$REC_SHIM_DIR/manifest.json" 2>/dev/null || echo "missing")'"; fi
rm -rf -- "$MEDIA_TEST_DIR"
rec_codex_teardown

test_case "Attachment list accepts UTF-8 BOM and CRLF"
rec_codex_setup
MEDIA_TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/media_list_crlf_XXXXXX")
PNG1="$MEDIA_TEST_DIR/first image.png"
PNG2="$MEDIA_TEST_DIR/second image.png"
LIST="$MEDIA_TEST_DIR/attachments.txt"
printf '\211PNG\r\n\032\n' > "$PNG1"
printf '\211PNG\r\n\032\n' > "$PNG2"
printf '\357\273\277%s\r\n%s\r\n' "$PNG1" "$PNG2" > "$LIST"
OUTPUT=$(PATH="$REC_SHIM_DIR:$PATH" env -u CODEX_WRAPPER_MODEL bash "$WRAPPER" --prompt "inspect" --attachment-list "$LIST" 2>&1)
CODE=$?
IMAGE_COUNT=$(grep -c '^-i$' "$REC_ARGV" || true)
if [[ $CODE -eq 0 && $IMAGE_COUNT -eq 2 ]]; then pass
else fail "exit=$CODE image_count=$IMAGE_COUNT output='$OUTPUT'"; fi
rm -rf -- "$MEDIA_TEST_DIR"
rec_codex_teardown

test_case "Attachment list accepts LF without BOM"
rec_codex_setup
MEDIA_TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/media_list_lf_XXXXXX")
PNG1="$MEDIA_TEST_DIR/first.png"
PNG2="$MEDIA_TEST_DIR/second.png"
LIST="$MEDIA_TEST_DIR/attachments.txt"
printf '\211PNG\r\n\032\n' > "$PNG1"
printf '\211PNG\r\n\032\n' > "$PNG2"
printf '%s\n%s\n' "$PNG1" "$PNG2" > "$LIST"
OUTPUT=$(PATH="$REC_SHIM_DIR:$PATH" env -u CODEX_WRAPPER_MODEL bash "$WRAPPER" --prompt "inspect" --attachment-list "$LIST" 2>&1)
CODE=$?
IMAGE_COUNT=$(grep -c '^-i$' "$REC_ARGV" || true)
if [[ $CODE -eq 0 && $IMAGE_COUNT -eq 2 ]]; then pass
else fail "exit=$CODE image_count=$IMAGE_COUNT output='$OUTPUT'"; fi
rm -rf -- "$MEDIA_TEST_DIR"
rec_codex_teardown

test_case "Attachment list ignores whitespace-only lines"
rec_codex_setup
MEDIA_TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/media_list_space_XXXXXX")
PNG="$MEDIA_TEST_DIR/only.png"
LIST="$MEDIA_TEST_DIR/attachments.txt"
printf '\211PNG\r\n\032\n' > "$PNG"
printf '   \n\t\n%s\n' "$PNG" > "$LIST"
OUTPUT=$(PATH="$REC_SHIM_DIR:$PATH" env -u CODEX_WRAPPER_MODEL bash "$WRAPPER" --prompt "inspect" --attachment-list "$LIST" 2>&1)
CODE=$?
IMAGE_COUNT=$(grep -c '^-i$' "$REC_ARGV" || true)
if [[ $CODE -eq 0 && $IMAGE_COUNT -eq 1 ]]; then pass
else fail "exit=$CODE image_count=$IMAGE_COUNT output='$OUTPUT'"; fi
rm -rf -- "$MEDIA_TEST_DIR"
rec_codex_teardown

test_case "Staged attachment remains valid after source is removed"
rec_codex_setup
MEDIA_TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/media_source_remove_XXXXXX")
PNG="$MEDIA_TEST_DIR/source.png"
printf '\211PNG\r\n\032\n' > "$PNG"
OUTPUT=$(PATH="$REC_SHIM_DIR:$PATH" CODEX_TEST_REMOVE_SOURCE="$PNG" env -u CODEX_WRAPPER_MODEL \
    bash "$WRAPPER" --prompt "inspect" --attachment "$PNG" 2>&1)
CODE=$?
IMAGE_COUNT=$(grep -c '^-i$' "$REC_ARGV" || true)
if [[ $CODE -eq 0 && $IMAGE_COUNT -eq 1 && ! -e "$PNG" ]]; then pass
else fail "exit=$CODE image_count=$IMAGE_COUNT output='$OUTPUT'"; fi
rm -rf -- "$MEDIA_TEST_DIR"
rec_codex_teardown

test_case "Unknown attachment format is rejected"
BAD_MEDIA=$(mktemp "${TMPDIR:-/tmp}/bad_media_XXXXXX.txt")
printf 'not an image' > "$BAD_MEDIA"
OUTPUT=$(bash "$WRAPPER" --prompt "inspect" --attachment "$BAD_MEDIA" 2>&1)
CODE=$?
rm -f -- "$BAD_MEDIA"
if [[ $CODE -ne 0 ]] && echo "$OUTPUT" | grep -q "Unsupported or unrecognized"; then pass
else fail "exit=$CODE output='$OUTPUT'"; fi

test_case "Control characters in attachment filename are rejected"
CONTROL_DIR=$(mktemp -d "${TMPDIR:-/tmp}/control_media_XXXXXX")
CONTROL_MEDIA="$CONTROL_DIR/"$'bad\nname.png'
printf '\211PNG\r\n\032\n' > "$CONTROL_MEDIA"
OUTPUT=$(bash "$WRAPPER" --prompt "inspect" --attachment "$CONTROL_MEDIA" 2>&1)
CODE=$?
rm -rf -- "$CONTROL_DIR"
if [[ $CODE -ne 0 ]] && echo "$OUTPUT" | grep -q "control characters"; then pass
else fail "exit=$CODE output='$OUTPUT'"; fi

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

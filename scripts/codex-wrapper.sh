#!/usr/bin/env bash
# codex-wrapper.sh - Invoke Codex CLI non-interactively from Claude Code
# Usage: bash codex-wrapper.sh --prompt "your question" [options]
#
# Options:
#   --prompt        (required) The prompt to send to Codex
#   --model         (optional) Model name
#   --timeout       (optional) Timeout in seconds (default: 120)
#   --workdir       (optional) Working directory for codex (default: /tmp)
#   --context       (optional) Additional context to prepend to the prompt
#   --context-file  (optional) Path to a file containing context (avoids cmdline length limits)

set -euo pipefail

PROMPT=""
MODEL=""
TIMEOUT=120
WORKDIR=""
CONTEXT=""
CONTEXT_FILE=""

# Max context size in bytes before warning (100KB)
MAX_CONTEXT_SIZE=102400

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --prompt)       PROMPT="$2"; shift 2 ;;
        --model)        MODEL="$2"; shift 2 ;;
        --timeout)      TIMEOUT="$2"; shift 2 ;;
        --workdir)      WORKDIR="$2"; shift 2 ;;
        --context)      CONTEXT="$2"; shift 2 ;;
        --context-file) CONTEXT_FILE="$2"; shift 2 ;;
        *) echo "Error: Unknown option: $1" >&2; exit 1 ;;
    esac
done

# --- Input validation ---
if [[ -z "$PROMPT" ]]; then
    echo "Error: --prompt is required." >&2
    exit 1
fi

# --- Load context from file if specified ---
if [[ -n "$CONTEXT_FILE" ]]; then
    if [[ ! -f "$CONTEXT_FILE" ]]; then
        echo "Error: Context file not found: $CONTEXT_FILE" >&2
        exit 1
    fi
    CONTEXT=$(cat "$CONTEXT_FILE")
fi

# --- Context size warning ---
if [[ -n "$CONTEXT" ]]; then
    CONTEXT_SIZE=${#CONTEXT}
    if [[ $CONTEXT_SIZE -gt $MAX_CONTEXT_SIZE ]]; then
        echo "Warning: Context is large ($(( CONTEXT_SIZE / 1024 ))KB). This may slow down the request." >&2
    fi
fi

# --- Determine safe working directory ---
if [[ -z "$WORKDIR" ]]; then
    WORKDIR="${TMPDIR:-/tmp}"
fi

# --- Build the full prompt ---
if [[ -n "$CONTEXT" ]]; then
    FULL_PROMPT="${CONTEXT}

---

${PROMPT}"
else
    FULL_PROMPT="$PROMPT"
fi

# --- Temp files ---
OUT_FILE=$(mktemp "${TMPDIR:-/tmp}/codex_out_XXXXXX.txt")
ERR_FILE=$(mktemp "${TMPDIR:-/tmp}/codex_err_XXXXXX.txt")

cleanup() {
    rm -f "$OUT_FILE" "$ERR_FILE"
}
trap cleanup EXIT

# --- Build codex command (-- separates options from prompt) ---
CODEX_ARGS=(exec -C "$WORKDIR" --skip-git-repo-check --ephemeral -o "$OUT_FILE")

if [[ -n "$MODEL" ]]; then
    CODEX_ARGS+=(-m "$MODEL")
fi

CODEX_ARGS+=(--)
CODEX_ARGS+=("$FULL_PROMPT")

# --- Execute with timeout ---
CODEX_EXIT=0
if command -v timeout &>/dev/null; then
    timeout "${TIMEOUT}s" codex "${CODEX_ARGS[@]}" 2>"$ERR_FILE" || CODEX_EXIT=$?
    if [[ $CODEX_EXIT -eq 124 ]]; then
        echo "Error: Codex CLI timed out after ${TIMEOUT}s" >&2
        exit 2
    fi
elif command -v gtimeout &>/dev/null; then
    gtimeout "${TIMEOUT}s" codex "${CODEX_ARGS[@]}" 2>"$ERR_FILE" || CODEX_EXIT=$?
    if [[ $CODEX_EXIT -eq 124 ]]; then
        echo "Error: Codex CLI timed out after ${TIMEOUT}s" >&2
        exit 2
    fi
else
    # Fallback: no timeout command available (timeout disabled)
    codex "${CODEX_ARGS[@]}" 2>"$ERR_FILE" || CODEX_EXIT=$?
fi

# --- Read output ---
if [[ -f "$OUT_FILE" ]]; then
    OUTPUT=$(cat "$OUT_FILE")
    OUTPUT=$(echo "$OUTPUT" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    if [[ -n "$OUTPUT" ]]; then
        echo "$OUTPUT"
    else
        echo "Codex CLI returned empty output." >&2
        if [[ -s "$ERR_FILE" ]]; then
            echo "Stderr:" >&2
            cat "$ERR_FILE" >&2
        fi
        exit 1
    fi
else
    echo "Codex CLI produced no output file. Exit code: $CODEX_EXIT" >&2
    if [[ -s "$ERR_FILE" ]]; then
        echo "Stderr:" >&2
        cat "$ERR_FILE" >&2
    fi
    exit 1
fi

# Propagate non-zero exit from codex (even if output was produced)
if [[ $CODEX_EXIT -ne 0 ]]; then
    exit $CODEX_EXIT
fi

exit 0

#!/usr/bin/env bash
# codex-wrapper.sh - Invoke Codex CLI non-interactively from Claude Code
# Usage: bash codex-wrapper.sh --prompt "your question" [options]
#
# Options:
#   --prompt   (required) The prompt to send to Codex
#   --model    (optional) Model name
#   --timeout  (optional) Timeout in seconds (default: 120)
#   --workdir  (optional) Working directory for codex (default: /tmp)
#   --context  (optional) Additional context to prepend to the prompt

set -euo pipefail

PROMPT=""
MODEL=""
TIMEOUT=120
WORKDIR=""
CONTEXT=""

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --prompt)  PROMPT="$2"; shift 2 ;;
        --model)   MODEL="$2"; shift 2 ;;
        --timeout) TIMEOUT="$2"; shift 2 ;;
        --workdir) WORKDIR="$2"; shift 2 ;;
        --context) CONTEXT="$2"; shift 2 ;;
        *) echo "Error: Unknown option: $1" >&2; exit 1 ;;
    esac
done

# --- Input validation ---
if [[ -z "$PROMPT" ]]; then
    echo "Error: --prompt is required." >&2
    exit 1
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

# --- Temp file for output ---
OUT_FILE=$(mktemp "${TMPDIR:-/tmp}/codex_out_XXXXXX.txt")

cleanup() {
    rm -f "$OUT_FILE"
}
trap cleanup EXIT

# --- Build codex command ---
CODEX_ARGS=(exec -C "$WORKDIR" --skip-git-repo-check --ephemeral -o "$OUT_FILE")

if [[ -n "$MODEL" ]]; then
    CODEX_ARGS+=(-m "$MODEL")
fi

CODEX_ARGS+=("$FULL_PROMPT")

# --- Execute with timeout ---
if command -v timeout &>/dev/null; then
    # GNU coreutils timeout
    timeout "${TIMEOUT}s" codex "${CODEX_ARGS[@]}" 2>/dev/null
    EXIT_CODE=$?
    if [[ $EXIT_CODE -eq 124 ]]; then
        echo "Error: Codex CLI timed out after ${TIMEOUT}s" >&2
        exit 2
    fi
elif command -v gtimeout &>/dev/null; then
    # macOS with coreutils installed via Homebrew
    gtimeout "${TIMEOUT}s" codex "${CODEX_ARGS[@]}" 2>/dev/null
    EXIT_CODE=$?
    if [[ $EXIT_CODE -eq 124 ]]; then
        echo "Error: Codex CLI timed out after ${TIMEOUT}s" >&2
        exit 2
    fi
else
    # Fallback: no timeout command available
    codex "${CODEX_ARGS[@]}" 2>/dev/null
    EXIT_CODE=$?
fi

# --- Read output ---
if [[ -f "$OUT_FILE" ]]; then
    OUTPUT=$(cat "$OUT_FILE")
    OUTPUT=$(echo "$OUTPUT" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    if [[ -n "$OUTPUT" ]]; then
        echo "$OUTPUT"
    else
        echo "Codex CLI returned empty output." >&2
        exit 1
    fi
else
    echo "Codex CLI produced no output file." >&2
    exit 1
fi

exit 0

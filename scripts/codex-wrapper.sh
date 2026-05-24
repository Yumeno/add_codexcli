#!/usr/bin/env bash
# codex-wrapper.sh - Invoke Codex CLI non-interactively from Claude Code
# Usage: bash codex-wrapper.sh --prompt "your question" [options]
#
# Options:
#   --prompt        (required for invocation) The prompt to send to Codex
#   --model         (optional) Model name
#   --timeout       (optional) Timeout in seconds (default: 120)
#   --workdir       (optional) Working directory for codex (default: /tmp)
#   --context       (optional) Additional context to prepend to the prompt
#   --context-file  (optional) Path to a file containing context (avoids cmdline length limits)
#
# Config subcommands (do not invoke codex):
#   --set-model NAME  Persist NAME as the default model in codex-wrapper.conf
#   --show-model      Print the currently resolved model and its source, then exit

set -euo pipefail

PROMPT=""
MODEL=""
TIMEOUT=120
WORKDIR=""
CONTEXT=""
CONTEXT_FILE=""
SET_MODEL=""
SHOW_MODEL=""

# Max context size in bytes before warning (100KB)
MAX_CONTEXT_SIZE=102400

# Config file lives next to this script. Same relative position whether the
# install is project-local (<proj>/scripts/) or global (~/.claude/scripts/).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/codex-wrapper.conf"

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --prompt)       PROMPT="$2"; shift 2 ;;
        --model)        MODEL="$2"; shift 2 ;;
        --timeout)      TIMEOUT="$2"; shift 2 ;;
        --workdir)      WORKDIR="$2"; shift 2 ;;
        --context)      CONTEXT="$2"; shift 2 ;;
        --context-file) CONTEXT_FILE="$2"; shift 2 ;;
        --set-model)    SET_MODEL="$2"; shift 2 ;;
        --show-model)   SHOW_MODEL=1; shift ;;
        *) echo "Error: Unknown option: $1" >&2; exit 1 ;;
    esac
done

# --- Helper: extract `model=value` from config file ---
read_config_model() {
    [[ -f "$CONFIG_FILE" ]] || return 0
    grep -E '^[[:space:]]*model[[:space:]]*=' "$CONFIG_FILE" \
        | grep -vE '^[[:space:]]*#' \
        | head -1 \
        | sed -E 's/^[[:space:]]*model[[:space:]]*=[[:space:]]*//' \
        | sed -E 's/[[:space:]]+$//' \
        | sed -E 's/^"(.*)"$/\1/' \
        | sed -E "s/^'(.*)'\$/\1/"
}

# --- Subcommand: --set-model (write config, exit before validation) ---
if [[ -n "$SET_MODEL" ]]; then
    # Allow model-name-like identifiers only. Blocks $, `, ;, spaces, etc.
    if [[ ! "$SET_MODEL" =~ ^[A-Za-z0-9._:/-]+$ ]]; then
        echo "Error: model name '$SET_MODEL' contains unsafe characters." >&2
        echo "       Allowed: A-Z a-z 0-9 . _ : / -" >&2
        exit 1
    fi
    cat > "$CONFIG_FILE" <<CONFEOF
# codex-wrapper.conf
# Default options for codex-wrapper.sh / codex-wrapper.ps1.
# Edit this file directly, or use:
#   bash codex-wrapper.sh --set-model <name>
#
# Lookup priority for the model:
#   1. --model / -Model CLI flag
#   2. \$CODEX_WRAPPER_MODEL environment variable
#   3. this file (model=...)
#   4. unset (codex CLI default)

model=$SET_MODEL
CONFEOF
    echo "Saved model='$SET_MODEL' to $CONFIG_FILE"
    exit 0
fi

# --- Resolve effective model (priority: --model > env > config) ---
MODEL_SOURCE=""
if [[ -n "$MODEL" ]]; then
    MODEL_SOURCE="cli"
elif [[ -n "${CODEX_WRAPPER_MODEL:-}" ]]; then
    MODEL="$CODEX_WRAPPER_MODEL"
    MODEL_SOURCE="env"
else
    CONFIG_MODEL=$(read_config_model)
    if [[ -n "$CONFIG_MODEL" ]]; then
        MODEL="$CONFIG_MODEL"
        MODEL_SOURCE="config"
    fi
fi

# --- Subcommand: --show-model (print resolved model, exit) ---
if [[ -n "$SHOW_MODEL" ]]; then
    if [[ -n "$MODEL" ]]; then
        echo "model=$MODEL (source: $MODEL_SOURCE)"
        if [[ "$MODEL_SOURCE" == "config" ]]; then
            echo "config_file=$CONFIG_FILE"
        fi
    else
        echo "model=(unset; codex CLI default will be used)"
        if [[ -f "$CONFIG_FILE" ]]; then
            echo "config_file=$CONFIG_FILE (no model= entry)"
        else
            echo "config_file=$CONFIG_FILE (does not exist)"
        fi
    fi
    exit 0
fi

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
    # Announce the resolved model on stderr so callers (e.g. SKILLs) can
    # display it without guessing. Emitted whenever we have a concrete model
    # (cli / env / config); when nothing resolved we stay silent because we
    # cannot know which model codex itself picked.
    echo "MODEL: $MODEL" >&2
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

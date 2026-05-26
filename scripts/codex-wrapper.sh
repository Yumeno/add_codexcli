#!/usr/bin/env bash
# codex-wrapper.sh - Invoke Codex CLI non-interactively from Claude Code
# Usage: bash codex-wrapper.sh --prompt "your question" [options]
#
# Options:
#   --prompt        (required for invocation) The prompt to send to Codex
#   --model         (optional) Model name
#   --timeout       (optional) Timeout in seconds (default: 120)
#   --workdir       (optional) Working directory for codex (default: ASCII temp)
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

# Single regex used to validate every model name we touch, regardless of source
# (CLI flag, env var, conf file, --set-model). The wrapper announces the model
# on stderr as `MODEL: <name>` and SKILLs grep that line back out, so any
# newline or shell-meta character here is a protocol-spoofing vector.
MODEL_NAME_RE='^[A-Za-z0-9._:/-]+$'

validate_model() {
    # $1: value, $2: source label (for the error message)
    local value="$1" source="$2"
    if [[ ! "$value" =~ $MODEL_NAME_RE ]]; then
        echo "Error: model name from $source contains unsafe characters: '$value'" >&2
        echo "       Allowed: A-Z a-z 0-9 . _ : / -" >&2
        exit 1
    fi
}

# --- Helper: require a value argument for an option ---
# Usage: require_value <option-name> <remaining-arg-count> "<next-arg>"
#   <remaining-arg-count>: $# from the caller AFTER the option, so $# >= 1
#                         means a value-token is present.
#   <next-arg>:           the value-token itself (may be "--something"). Empty
#                         string and a -- prefix both count as "missing".
require_value() {
    local opt="$1" remaining="$2" next="${3:-}"
    if [[ "$remaining" -lt 1 || -z "$next" || "$next" == --* ]]; then
        echo "Error: $opt requires a value." >&2
        exit 1
    fi
}

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --prompt)       require_value "$1" "$(( $# - 1 ))" "${2:-}"; PROMPT="$2"; shift 2 ;;
        --model)        require_value "$1" "$(( $# - 1 ))" "${2:-}"; MODEL="$2"; shift 2 ;;
        --timeout)      require_value "$1" "$(( $# - 1 ))" "${2:-}"; TIMEOUT="$2"; shift 2 ;;
        --workdir)      require_value "$1" "$(( $# - 1 ))" "${2:-}"; WORKDIR="$2"; shift 2 ;;
        --context)      require_value "$1" "$(( $# - 1 ))" "${2:-}"; CONTEXT="$2"; shift 2 ;;
        --context-file) require_value "$1" "$(( $# - 1 ))" "${2:-}"; CONTEXT_FILE="$2"; shift 2 ;;
        --set-model)    require_value "$1" "$(( $# - 1 ))" "${2:-}"; SET_MODEL="$2"; shift 2 ;;
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

# --- Subcommand: --set-model (write config) ---
if [[ -n "$SET_MODEL" ]]; then
    validate_model "$SET_MODEL" "--set-model"
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
    validate_model "$MODEL" "--model"
    MODEL_SOURCE="cli"
elif [[ -n "${CODEX_WRAPPER_MODEL:-}" ]]; then
    validate_model "$CODEX_WRAPPER_MODEL" "\$CODEX_WRAPPER_MODEL"
    MODEL="$CODEX_WRAPPER_MODEL"
    MODEL_SOURCE="env"
else
    CONFIG_MODEL=$(read_config_model)
    if [[ -n "$CONFIG_MODEL" ]]; then
        validate_model "$CONFIG_MODEL" "$CONFIG_FILE"
        MODEL="$CONFIG_MODEL"
        MODEL_SOURCE="config"
    fi
fi

# --- Subcommand: --show-model (print resolved model, exit) ---
if [[ -n "$SHOW_MODEL" ]]; then
    if [[ -n "$MODEL" ]]; then
        # MODEL has been validate_model()'d above, so printing it here cannot
        # smuggle extra lines or shell metacharacters.
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

if [[ ! "$TIMEOUT" =~ ^[0-9]+$ || "$TIMEOUT" -le 0 ]]; then
    echo "Error: --timeout must be a positive integer (got: '$TIMEOUT')." >&2
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

# --- Resolve & verify an ASCII-only working directory ---
# Codex CLI's WebSocket layer fails on non-ASCII paths, so a non-ASCII workdir
# is a hard error. Resolution chain mirrors codex-wrapper.ps1:
#   1. --workdir if given (ASCII-checked)
#   2. $CODEX_WRAPPER_TEMP env var
#   3. $TMPDIR / /tmp if ASCII
#   4. auto-create /tmp/codex-wrapper-$$
#   5. explicit error
is_ascii() {
    # Returns 0 if $1 contains only printable ASCII (no control chars besides /).
    LC_ALL=C grep -q '^[ -~]*$' <<< "$1"
}

resolve_workdir() {
    local candidate=""
    if [[ -n "$WORKDIR" ]]; then
        if ! is_ascii "$WORKDIR"; then
            echo "Error: --workdir must be ASCII-only due to Codex CLI WebSocket limitations: $WORKDIR" >&2
            exit 1
        fi
        candidate="$WORKDIR"
    elif [[ -n "${CODEX_WRAPPER_TEMP:-}" ]]; then
        if ! is_ascii "$CODEX_WRAPPER_TEMP"; then
            echo "Error: \$CODEX_WRAPPER_TEMP must be ASCII-only: $CODEX_WRAPPER_TEMP" >&2
            exit 1
        fi
        candidate="$CODEX_WRAPPER_TEMP"
    else
        local tmp="${TMPDIR:-/tmp}"
        if is_ascii "$tmp"; then
            candidate="$tmp"
        else
            # Build a per-process ASCII fallback under /tmp.
            candidate="/tmp/codex-wrapper-$$"
            if ! mkdir -p "$candidate" 2>/dev/null; then
                echo "Error: \$TMPDIR is non-ASCII ('$tmp') and fallback '$candidate' is not creatable." >&2
                echo "       Set \$CODEX_WRAPPER_TEMP or --workdir to an ASCII directory." >&2
                exit 1
            fi
        fi
    fi
    if [[ ! -d "$candidate" ]]; then
        echo "Error: workdir does not exist: $candidate" >&2
        exit 1
    fi
    WORKDIR="$candidate"
}
resolve_workdir

# --- Build the full prompt ---
if [[ -n "$CONTEXT" ]]; then
    FULL_PROMPT="${CONTEXT}

---

${PROMPT}"
else
    FULL_PROMPT="$PROMPT"
fi

# --- Temp files (placed under the validated ASCII workdir) ---
OUT_FILE=$(mktemp "$WORKDIR/codex_out_XXXXXX.txt")
ERR_FILE=$(mktemp "$WORKDIR/codex_err_XXXXXX.txt")

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

#!/usr/bin/env bash
# codex-wrapper.sh - Invoke Codex CLI non-interactively from Claude Code
# Usage: bash codex-wrapper.sh --prompt "your question" [options]
#
# Options:
#   --prompt        (required for invocation) The prompt to send to Codex
#   --model         (optional) Model name
#   --timeout       (optional) Timeout in seconds (default: 120)
#   --cd            (optional) Working directory for codex (default: ASCII temp)
#   --workdir       (optional, alias for --cd; kept for backward compatibility)
#   --context       (optional) Additional context to prepend to the prompt
#   --context-file  (optional) Path to a file containing context (avoids cmdline length limits)
#   --sandbox MODE  (optional) Codex sandbox mode: read-only | workspace-write | danger-full-access
#                   Default: read-only. Matches codex CLI's implicit default for non-VCS workdirs
#                   and prevents the workspace-write+on-request stall when --cd points at a git repo.
#
# Config subcommands (do not invoke codex):
#   --set-model NAME  Persist NAME as the default model in codex-wrapper.conf
#   --show-model      Print the currently resolved model and its source, then exit

set -euo pipefail

# Sentinel printed to stdout on every failure path so callers that cannot
# separate stdout/stderr (the documented "bare single command" SKILL.md
# invocation under Claude Code's permit umbrella) can still detect failure
# from the stdout stream alone. See issue #19 review feedback / issue #20.
ERROR_SENTINEL="[CODEX_WRAPPER_ERROR]"

# die <exit_code> <human-readable-error-message>
# Emits "<SENTINEL> <message>" to stdout, the same message to stderr (for
# anyone who *does* separate streams or reads logs directly), then exits.
die() {
    local code="$1"; shift
    local msg="$*"
    printf '%s %s\n' "$ERROR_SENTINEL" "$msg"
    printf 'Error: %s\n' "$msg" >&2
    exit "$code"
}

PROMPT=""
MODEL=""
TIMEOUT=120
WORKDIR=""
CONTEXT=""
CONTEXT_FILE=""
HAS_CONTEXT=0
ATTACHMENTS=()
ATTACHMENT_LIST=""
SANDBOX="read-only"
SET_MODEL=""
SHOW_MODEL=""

# Exit status from the codex subprocess. Pre-initialised so it is always
# defined under `set -u`, regardless of which timeout branch we land in.
CODEX_EXIT=0

# Sandbox modes accepted by `codex exec -s`. Anything outside this set is
# rejected before we hand off to codex, both to fail fast on typos and to keep
# wrapper behaviour stable when the Codex CLI gains new modes (those would need
# an explicit wrapper update, which is the safer default for a wrapper).
SANDBOX_MODES_RE='^(read-only|workspace-write|danger-full-access)$'

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
        die 1 "model name from $source contains unsafe characters: '$value' (allowed: A-Z a-z 0-9 . _ : / -)"
    fi
}

# --- Helper: require a value argument for an option ---
# Usage: require_value <option-name> <remaining-arg-count> "<next-arg>"
#   <remaining-arg-count>: $# from the caller AFTER the option, so >= 1
#                         means a value-token is present.
#   <next-arg>:           the value-token itself; only "missing" if absent.
# We intentionally accept values that start with "--", e.g. a prompt of
# "--help": the wrapper passes the prompt to codex via stdin (and uses the
# `--` separator when not), so a leading-dash value cannot be misparsed as an
# option later. Treating it as "missing" here would break that contract.
require_value() {
    local opt="$1" remaining="$2"
    if [[ "$remaining" -lt 1 ]]; then
        die 1 "$opt requires a value."
    fi
}

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --prompt)       require_value "$1" "$(( $# - 1 ))" "${2:-}"; PROMPT="$2"; shift 2 ;;
        --model)        require_value "$1" "$(( $# - 1 ))" "${2:-}"; MODEL="$2"; shift 2 ;;
        --timeout)      require_value "$1" "$(( $# - 1 ))" "${2:-}"; TIMEOUT="$2"; shift 2 ;;
        --cd|--workdir) require_value "$1" "$(( $# - 1 ))" "${2:-}"; WORKDIR="$2"; shift 2 ;;
        --context)      require_value "$1" "$(( $# - 1 ))" "${2:-}"; CONTEXT="$2"; HAS_CONTEXT=1; shift 2 ;;
        --context-file) require_value "$1" "$(( $# - 1 ))" "${2:-}"; CONTEXT_FILE="$2"; shift 2 ;;
        --attachment)   require_value "$1" "$(( $# - 1 ))" "${2:-}"; ATTACHMENTS+=("$2"); shift 2 ;;
        --attachment-list) require_value "$1" "$(( $# - 1 ))" "${2:-}"; ATTACHMENT_LIST="$2"; shift 2 ;;
        --sandbox)      require_value "$1" "$(( $# - 1 ))" "${2:-}"; SANDBOX="$2"; shift 2 ;;
        --set-model)    require_value "$1" "$(( $# - 1 ))" "${2:-}"; SET_MODEL="$2"; shift 2 ;;
        --show-model)   SHOW_MODEL=1; shift ;;
        *) die 1 "Unknown option: $1" ;;
    esac
done

# --- Helper: extract `model=value` from config file ---
# Implemented as a single awk script so a comment-only conf (or one missing the
# model= line entirely) returns cleanly with no output, instead of the
# grep-pipeline pattern that, under `set -euo pipefail`, would treat a no-match
# as failure and kill the whole script.
read_config_model() {
    [[ -f "$CONFIG_FILE" ]] || return 0
    awk '
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*model[[:space:]]*=/ {
            sub(/^[[:space:]]*model[[:space:]]*=[[:space:]]*/, "")
            sub(/[[:space:]]+$/, "")
            if (match($0, /^".*"$/) || match($0, /^'\''.*'\''$/)) {
                $0 = substr($0, 2, length($0) - 2)
            }
            print
            exit
        }
    ' "$CONFIG_FILE"
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
    die 1 "--prompt is required."
fi

if [[ ! "$TIMEOUT" =~ ^[0-9]+$ || "$TIMEOUT" -le 0 ]]; then
    die 1 "--timeout must be a positive integer (got: '$TIMEOUT')."
fi

# --- Sandbox validation ---
# Done after parse so a typo in --sandbox surfaces before we resolve the model
# or touch the filesystem.
if [[ ! "$SANDBOX" =~ $SANDBOX_MODES_RE ]]; then
    die 1 "--sandbox must be one of: read-only | workspace-write | danger-full-access (got: '$SANDBOX')."
fi

# --- Load context from file if specified ---
if [[ -n "$CONTEXT_FILE" ]]; then
    if [[ ! -f "$CONTEXT_FILE" ]]; then
        die 1 "Context file not found: $CONTEXT_FILE"
    fi
    # Preserve "context was requested" even if the file is empty: an empty
    # context-file means the caller wanted *no extra context*, not "fall back
    # to argv-only behaviour". Tests rely on this distinction.
    CONTEXT=$(cat "$CONTEXT_FILE")
    HAS_CONTEXT=1
fi

# --- Context size warning ---
if [[ "$HAS_CONTEXT" -eq 1 ]]; then
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
            die 1 "--workdir must be ASCII-only due to Codex CLI WebSocket limitations: $WORKDIR"
        fi
        candidate="$WORKDIR"
    elif [[ -n "${CODEX_WRAPPER_TEMP:-}" ]]; then
        if ! is_ascii "$CODEX_WRAPPER_TEMP"; then
            die 1 "\$CODEX_WRAPPER_TEMP must be ASCII-only: $CODEX_WRAPPER_TEMP"
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
                die 1 "\$TMPDIR is non-ASCII ('$tmp') and fallback '$candidate' is not creatable. Set \$CODEX_WRAPPER_TEMP or --workdir to an ASCII directory."
            fi
        fi
    fi
    if [[ ! -d "$candidate" ]]; then
        die 1 "workdir does not exist: $candidate"
    fi
    WORKDIR="$candidate"
}
resolve_workdir

if [[ -n "$ATTACHMENT_LIST" ]]; then
    [[ -f "$ATTACHMENT_LIST" ]] || die 1 "Attachment list not found: $ATTACHMENT_LIST"
    while IFS= read -r path || [[ -n "$path" ]]; do
        [[ -n "$path" ]] && ATTACHMENTS+=("$path")
    done < "$ATTACHMENT_LIST"
fi

MEDIA_DIR=""
MEDIA_PATHS=()
stage_attachments() {
    [[ ${#ATTACHMENTS[@]} -gt 0 ]] || return 0
    local media_root="${CODEX_WRAPPER_TEMP:-${TMPDIR:-/tmp}}"
    is_ascii "$media_root" || media_root="/tmp"
    mkdir -p -- "$media_root"
    MEDIA_DIR=$(mktemp -d "$media_root/codex-media.XXXXXX")
    local order=0 total=0 path header mime ext staged size
    local json_entries=()
    for path in "${ATTACHMENTS[@]}"; do
        order=$((order + 1))
        [[ -f "$path" && ! -L "$path" ]] || die 1 "Attachment not found, not regular, or symlink: $path"
        size=$(wc -c < "$path")
        [[ "$size" -gt 0 ]] || die 1 "Attachment must not be empty: $path"
        header=$(od -An -tx1 -N8 "$path" | tr -d ' \r\n')
        case "$header" in
            89504e470d0a1a0a*) mime="image/png"; ext=".png" ;;
            ffd8ff*) mime="image/jpeg"; ext=".jpg" ;;
            *) die 1 "Unsupported or unrecognized attachment format: $path (currently allowed: PNG, JPEG)" ;;
        esac
        staged=$(printf '%s/image-%03d%s' "$MEDIA_DIR" "$order" "$ext")
        cp -- "$path" "$staged"
        MEDIA_PATHS+=("$staged")
        total=$((total + size))
        printf 'MEDIA_ITEM: order=%d mime=%s bytes=%d support=probe-verified\n' "$order" "$mime" "$size" >&2

        local orig_name
        orig_name=$(basename -- "$path")
        local esc_orig_name="${orig_name//\\/\\\\}"
        esc_orig_name="${esc_orig_name//\"/\\\"}"
        local esc_staged="${staged//\\/\\\\}"
        esc_staged="${esc_staged//\"/\\\"}"

        json_entries+=( "  {
    \"order\": $order,
    \"original_name\": \"$esc_orig_name\",
    \"staged_path\": \"$esc_staged\",
    \"mime\": \"$mime\",
    \"bytes\": $size,
    \"support\": \"probe-verified\"
  }" )
    done
    if [[ ${#json_entries[@]} -gt 0 ]]; then
        {
            echo "["
            for ((i=0; i<${#json_entries[@]}; i++)); do
                if ((i > 0)); then
                    echo ","
                fi
                echo "${json_entries[i]}"
            done
            echo "]"
        } > "$MEDIA_DIR/manifest.json"
    fi
    printf 'MEDIA: count=%d bytes=%d\n' "${#MEDIA_PATHS[@]}" "$total" >&2
}

# --- Temp files (placed under the validated ASCII workdir) ---
OUT_FILE=$(mktemp "$WORKDIR/codex_out_XXXXXX.txt")
ERR_FILE=$(mktemp "$WORKDIR/codex_err_XXXXXX.txt")

cleanup() {
    rm -f "$OUT_FILE" "$ERR_FILE"
    [[ -z "$MEDIA_DIR" || ! -d "$MEDIA_DIR" ]] || rm -rf -- "$MEDIA_DIR"
}
trap cleanup EXIT
stage_attachments

# --- Build codex command ---
# Context (if any) is streamed via stdin so it does not hit argv length limits
# and is not subject to shell quoting on the codex side. PROMPT stays on argv as
# the positional argument; `codex exec` documents that stdin is appended as a
# `<stdin>` block when both are provided.
#
# Sandbox: --sandbox is always passed. Default is read-only, which mirrors
# codex CLI's implicit default for non-VCS workdirs and avoids the
# workspace-write + on-request stall (540s timeout per issue #14) when --cd
# resolves to a git repository.
CODEX_ARGS=(exec -C "$WORKDIR" -s "$SANDBOX" --skip-git-repo-check --ephemeral -o "$OUT_FILE")

if [[ -n "$MODEL" ]]; then
    CODEX_ARGS+=(-m "$MODEL")
    # Announce the resolved model on stderr so callers (e.g. SKILLs) can
    # display it without guessing. Emitted whenever we have a concrete model
    # (cli / env / config); when nothing resolved we stay silent because we
    # cannot know which model codex itself picked.
    echo "MODEL: $MODEL" >&2
fi
for image in "${MEDIA_PATHS[@]}"; do
    CODEX_ARGS+=(-i "$image")
done

# `--` separates options from the prompt positional. We keep it even though
# require_value allows --*-leading values, because codex's own argv parser
# may not.
CODEX_ARGS+=(-- "$PROMPT")

# --- Execute with timeout ---
# When context is present, feed it via stdin using process substitution rather
# than a pipeline. A pipeline would put `codex` on the RHS of `|`, and under
# `set -euo pipefail` we would need PIPESTATUS gymnastics to extract codex's
# real exit code separately from printf's. Process substitution sidesteps both
# issues: codex's exit is the command's exit.
run_codex() {
    if [[ "$HAS_CONTEXT" -eq 1 ]]; then
        "$@" codex "${CODEX_ARGS[@]}" 2>"$ERR_FILE" < <(printf '%s' "$CONTEXT")
    else
        "$@" codex "${CODEX_ARGS[@]}" 2>"$ERR_FILE" </dev/null
    fi
}

if command -v timeout &>/dev/null; then
    run_codex timeout "${TIMEOUT}s" || CODEX_EXIT=$?
    if [[ $CODEX_EXIT -eq 124 ]]; then
        die 2 "Codex CLI timed out after ${TIMEOUT}s"
    fi
elif command -v gtimeout &>/dev/null; then
    run_codex gtimeout "${TIMEOUT}s" || CODEX_EXIT=$?
    if [[ $CODEX_EXIT -eq 124 ]]; then
        die 2 "Codex CLI timed out after ${TIMEOUT}s"
    fi
else
    # Fallback: no timeout command available (timeout disabled)
    run_codex || CODEX_EXIT=$?
fi

# --- Read output ---
if [[ -f "$OUT_FILE" ]]; then
    OUTPUT=$(cat "$OUT_FILE")
    OUTPUT=$(echo "$OUTPUT" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    if [[ -n "$OUTPUT" ]]; then
        echo "$OUTPUT"
    else
        # Codex ran but produced no usable content. We emit the sentinel + a
        # short reason on stdout (so skills detecting failure from the
        # combined stream still see it), and also dump codex's own stderr to
        # the wrapper's stderr for human debugging.
        printf '%s %s\n' "$ERROR_SENTINEL" "Codex CLI returned empty output (exit=$CODEX_EXIT)."
        echo "Error: Codex CLI returned empty output." >&2
        if [[ -s "$ERR_FILE" ]]; then
            echo "Stderr:" >&2
            cat "$ERR_FILE" >&2
        fi
        exit 1
    fi
else
    printf '%s %s\n' "$ERROR_SENTINEL" "Codex CLI produced no output file (exit=$CODEX_EXIT)."
    echo "Error: Codex CLI produced no output file. Exit code: $CODEX_EXIT" >&2
    if [[ -s "$ERR_FILE" ]]; then
        echo "Stderr:" >&2
        cat "$ERR_FILE" >&2
    fi
    exit 1
fi

# Propagate non-zero exit from codex (even if output was produced). The
# sentinel is added here too: codex produced *some* output (so we printed it
# above), but the run itself failed; without the sentinel the skill would see
# only the partial content and read it as a normal answer.
if [[ $CODEX_EXIT -ne 0 ]]; then
    printf '%s %s\n' "$ERROR_SENTINEL" "Codex CLI exited with non-zero status: $CODEX_EXIT"
    echo "Error: Codex CLI exited with non-zero status: $CODEX_EXIT" >&2
    exit $CODEX_EXIT
fi

exit 0

#!/usr/bin/env bash
# list-codex-models.sh - List models the codex CLI is aware of.
#
# Usage: bash list-codex-models.sh [--bundled] [--json]
#   --bundled  Use only the catalog bundled with the binary (no network).
#   --json     Print the raw JSON from `codex debug models` instead of names.
#
# Notes:
# - Runs from $TMPDIR (or /tmp) so non-ASCII cwd cannot trip codex's
#   WebSocket layer, mirroring the safety dance in codex-wrapper.sh.
# - No JSON parser dependency: name extraction is a best-effort grep/awk.
#   If the JSON shape changes and extraction yields nothing, the raw JSON
#   is printed as a fallback so the caller can still see the data.

set -euo pipefail

# Sentinel printed to stdout on every failure path so callers that cannot
# separate stdout/stderr can still detect failure from the stdout stream
# alone. Mirrors codex-wrapper.sh.
ERROR_SENTINEL="[CODEX_WRAPPER_ERROR]"

die() {
    local code="$1"; shift
    local msg="$*"
    printf '%s %s\n' "$ERROR_SENTINEL" "$msg"
    printf 'Error: %s\n' "$msg" >&2
    exit "$code"
}

BUNDLED=""
JSON_OUT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --bundled) BUNDLED="--bundled"; shift ;;
        --json)    JSON_OUT="1"; shift ;;
        -h|--help)
            sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) die 1 "Unknown option: $1" ;;
    esac
done

if ! command -v codex &>/dev/null; then
    die 1 "codex CLI not found in PATH"
fi

# Resolve an ASCII-only working directory the same way codex-wrapper.sh does.
# On a Linux box with a Japanese username, $TMPDIR / /tmp can itself be
# non-ASCII (e.g. /home/<jp>/tmp under some sandbox layouts), which would
# trip codex's WebSocket layer the moment we cd into it.
is_ascii() { LC_ALL=C grep -q '^[ -~]*$' <<< "$1"; }

resolve_ascii_workdir() {
    local cand=""
    if [[ -n "${CODEX_WRAPPER_TEMP:-}" ]]; then
        if ! is_ascii "$CODEX_WRAPPER_TEMP"; then
            die 1 "\$CODEX_WRAPPER_TEMP must be ASCII-only: $CODEX_WRAPPER_TEMP"
        fi
        cand="$CODEX_WRAPPER_TEMP"
    else
        local tmp="${TMPDIR:-/tmp}"
        if is_ascii "$tmp"; then
            cand="$tmp"
        else
            cand="/tmp/codex-wrapper-$$"
            if ! mkdir -p "$cand" 2>/dev/null; then
                die 1 "\$TMPDIR is non-ASCII ('$tmp') and fallback '$cand' is not creatable. Set \$CODEX_WRAPPER_TEMP to an ASCII directory."
            fi
        fi
    fi
    [[ -d "$cand" ]] || die 1 "workdir does not exist: $cand"
    printf '%s' "$cand"
}
WORKDIR=$(resolve_ascii_workdir)

if [[ -n "$BUNDLED" ]]; then
    RAW=$(cd "$WORKDIR" && codex debug models --bundled)
else
    RAW=$(cd "$WORKDIR" && codex debug models)
fi

if [[ -n "$JSON_OUT" ]]; then
    printf '%s\n' "$RAW"
    exit 0
fi

# Best-effort name extraction. Matches "id"/"name"/"slug" string fields,
# which covers the common shapes used by openai/codex's model catalog.
NAMES=$(printf '%s' "$RAW" \
    | grep -oE '"(id|name|slug)"[[:space:]]*:[[:space:]]*"[^"]+"' \
    | awk -F'"' '{print $4}' \
    | sort -u)

if [[ -n "$NAMES" ]]; then
    printf '%s\n' "$NAMES"
else
    # Schema drifted; fall back to raw JSON so the caller can still see it.
    echo "Warning: could not extract model names; printing raw JSON." >&2
    printf '%s\n' "$RAW"
fi

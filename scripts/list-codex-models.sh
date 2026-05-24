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

BUNDLED=""
JSON_OUT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --bundled) BUNDLED="--bundled"; shift ;;
        --json)    JSON_OUT="1"; shift ;;
        -h|--help)
            sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) echo "Error: Unknown option: $1" >&2; exit 1 ;;
    esac
done

if ! command -v codex &>/dev/null; then
    echo "Error: codex CLI not found in PATH" >&2
    exit 1
fi

WORKDIR="${TMPDIR:-/tmp}"

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

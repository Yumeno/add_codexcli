#!/usr/bin/env bash
# sync-skill-scripts.sh - Sync canonical helper scripts into skill bundles.
# Usage: bash tools/sync-skill-scripts.sh [--check]

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK=0

if [[ $# -gt 1 ]]; then
    printf '[SYNC_SKILL_SCRIPTS_ERROR] Usage: bash tools/sync-skill-scripts.sh [--check]\n' >&2
    exit 1
fi
if [[ $# -eq 1 ]]; then
    if [[ "$1" == "--check" ]]; then
        CHECK=1
    else
        printf '[SYNC_SKILL_SCRIPTS_ERROR] Usage: bash tools/sync-skill-scripts.sh [--check]\n' >&2
        exit 1
    fi
fi

die() {
    printf '[SYNC_SKILL_SCRIPTS_ERROR] %s\n' "$1" >&2
    exit 1
}

rel_path() {
    local path="$1"
    printf '%s\n' "${path#"$ROOT_DIR"/}"
}

skill_helpers() {
    case "$1" in
        ask-codex|ask-codex-with-context|set-codex-model)
            printf '%s\n' codex-wrapper.sh codex-wrapper.ps1
            ;;
        codex-implement)
            printf '%s\n' codex-wrapper.sh codex-wrapper.ps1 codex-verify.sh codex-verify.ps1
            ;;
        list-codex-models)
            printf '%s\n' codex-wrapper.sh codex-wrapper.ps1 list-codex-models.sh list-codex-models.ps1
            ;;
        *)
            return 1
            ;;
    esac
}

is_expected() {
    local candidate="$1"
    shift
    local expected
    for expected in "$@"; do
        [[ "$candidate" == "$expected" ]] && return 0
    done
    return 1
}

sync_skill() {
    local host_dir="$1"
    local skill="$2"
    local skill_dir="$ROOT_DIR/$host_dir/skills/$skill"
    local scripts_dir="$skill_dir/scripts"
    local helpers=()
    local helper

    [[ -d "$skill_dir" ]] || die "Skill directory not found: $(rel_path "$skill_dir")"
    mapfile -t helpers < <(skill_helpers "$skill")

    mkdir -p "$scripts_dir" || die "Failed to create scripts directory: $(rel_path "$scripts_dir")"
    find "$scripts_dir" -mindepth 1 -maxdepth 1 -type f -exec rm -f {} + ||
        die "Failed to clear scripts directory: $(rel_path "$scripts_dir")"

    for helper in "${helpers[@]}"; do
        [[ -f "$ROOT_DIR/scripts/$helper" ]] || die "Source helper not found: scripts/$helper"
        cp "$ROOT_DIR/scripts/$helper" "$scripts_dir/$helper" ||
            die "Failed to copy scripts/$helper to $(rel_path "$scripts_dir")"
    done

    printf 'synced %s: %d files\n' "$(rel_path "$skill_dir")" "${#helpers[@]}"
}

check_skill() {
    local host_dir="$1"
    local skill="$2"
    local skill_dir="$ROOT_DIR/$host_dir/skills/$skill"
    local scripts_dir="$skill_dir/scripts"
    local helpers=()
    local helper
    local file
    local basename
    local ok=0

    mapfile -t helpers < <(skill_helpers "$skill")

    if [[ ! -d "$scripts_dir" ]]; then
        printf 'scripts directory missing: %s\n' "$(rel_path "$skill_dir")" >&2
        return 1
    fi

    for helper in "${helpers[@]}"; do
        if [[ ! -f "$ROOT_DIR/scripts/$helper" ]]; then
            die "Source helper not found: scripts/$helper"
        fi
        if [[ ! -f "$scripts_dir/$helper" ]] ||
            ! cmp -s "$ROOT_DIR/scripts/$helper" "$scripts_dir/$helper"; then
            printf 'out of sync: %s\n' "$(rel_path "$scripts_dir/$helper")" >&2
            ok=1
        fi
    done

    while IFS= read -r -d '' file; do
        basename="$(basename "$file")"
        if ! is_expected "$basename" "${helpers[@]}"; then
            printf 'unexpected bundled script: %s\n' "$(rel_path "$file")" >&2
            ok=1
        fi
    done < <(find "$scripts_dir" -mindepth 1 -maxdepth 1 -type f -print0)

    return "$ok"
}

main() {
    local hosts=(.claude .agents)
    local skills=(ask-codex ask-codex-with-context codex-implement list-codex-models set-codex-model)
    local host
    local skill
    local failed=0

    for host in "${hosts[@]}"; do
        for skill in "${skills[@]}"; do
            if [[ "$CHECK" -eq 1 ]]; then
                check_skill "$host" "$skill" || failed=1
            else
                sync_skill "$host" "$skill"
            fi
        done
    done

    if [[ "$CHECK" -eq 1 ]]; then
        if [[ "$failed" -eq 0 ]]; then
            printf '%s\n' 'PASS: skill bundled scripts in sync'
        else
            exit 1
        fi
    fi
}

main "$@"

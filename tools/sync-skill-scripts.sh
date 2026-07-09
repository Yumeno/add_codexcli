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

make_dir() {
    local path="$1"
    (cd "$ROOT_DIR" && mkdir -p "$(rel_path "$path")")
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

skill_references() {
    case "$1" in
        codex-implement)
            printf '%s\n' image-generation.md
            ;;
        ask-codex|ask-codex-with-context|list-codex-models|set-codex-model)
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
    local references_dir="$skill_dir/references"
    local helpers=()
    local references=()
    local helper
    local reference

    [[ -d "$skill_dir" ]] || die "Skill directory not found: $(rel_path "$skill_dir")"
    mapfile -t helpers < <(skill_helpers "$skill")
    mapfile -t references < <(skill_references "$skill")

    make_dir "$scripts_dir" || die "Failed to create scripts directory: $(rel_path "$scripts_dir")"
    find "$scripts_dir" -mindepth 1 -maxdepth 1 -type f -exec rm -f {} + ||
        die "Failed to clear scripts directory: $(rel_path "$scripts_dir")"

    for helper in "${helpers[@]}"; do
        [[ -f "$ROOT_DIR/scripts/$helper" ]] || die "Source helper not found: scripts/$helper"
        cp "$ROOT_DIR/scripts/$helper" "$scripts_dir/$helper" ||
            die "Failed to copy scripts/$helper to $(rel_path "$scripts_dir")"
    done

    if [[ "${#references[@]}" -gt 0 ]]; then
        make_dir "$references_dir" || die "Failed to create references directory: $(rel_path "$references_dir")"
        find "$references_dir" -mindepth 1 -maxdepth 1 -type f -exec rm -f {} + ||
            die "Failed to clear references directory: $(rel_path "$references_dir")"
        for reference in "${references[@]}"; do
            [[ -f "$ROOT_DIR/docs/references/$reference" ]] || die "Source reference not found: docs/references/$reference"
            cp "$ROOT_DIR/docs/references/$reference" "$references_dir/$reference" ||
                die "Failed to copy docs/references/$reference to $(rel_path "$references_dir")"
        done
    elif [[ -d "$references_dir" ]]; then
        rm -rf "$references_dir" ||
            die "Failed to remove references directory: $(rel_path "$references_dir")"
    fi

    if [[ "${#references[@]}" -gt 0 ]]; then
        printf 'synced %s: %d scripts, %d reference\n' "$(rel_path "$skill_dir")" "${#helpers[@]}" "${#references[@]}"
    else
        printf 'synced %s: %d scripts\n' "$(rel_path "$skill_dir")" "${#helpers[@]}"
    fi
}

check_skill() {
    local host_dir="$1"
    local skill="$2"
    local skill_dir="$ROOT_DIR/$host_dir/skills/$skill"
    local scripts_dir="$skill_dir/scripts"
    local references_dir="$skill_dir/references"
    local helpers=()
    local references=()
    local helper
    local reference
    local file
    local basename
    local ok=0

    mapfile -t helpers < <(skill_helpers "$skill")
    mapfile -t references < <(skill_references "$skill")

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

    if [[ "${#references[@]}" -gt 0 ]]; then
        if [[ ! -d "$references_dir" ]]; then
            printf 'references directory missing: %s\n' "$(rel_path "$skill_dir")" >&2
            ok=1
        else
            for reference in "${references[@]}"; do
                if [[ ! -f "$ROOT_DIR/docs/references/$reference" ]]; then
                    die "Source reference not found: docs/references/$reference"
                fi
                if [[ ! -f "$references_dir/$reference" ]] ||
                    ! cmp -s "$ROOT_DIR/docs/references/$reference" "$references_dir/$reference"; then
                    printf 'out of sync: %s\n' "$(rel_path "$references_dir/$reference")" >&2
                    ok=1
                fi
            done

            while IFS= read -r -d '' file; do
                basename="$(basename "$file")"
                if ! is_expected "$basename" "${references[@]}"; then
                    printf 'unexpected bundled reference: %s\n' "$(rel_path "$file")" >&2
                    ok=1
                fi
            done < <(find "$references_dir" -mindepth 1 -maxdepth 1 -type f -print0)
        fi
    elif [[ -d "$references_dir" ]]; then
        printf 'unexpected references directory: %s\n' "$(rel_path "$references_dir")" >&2
        ok=1
    fi

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

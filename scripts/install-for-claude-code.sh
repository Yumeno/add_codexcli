#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd -- "$script_dir/.." && pwd)"
source_skills_root="$repository_root/.claude/skills"
destination_root="${1:-${HOME:?HOME is not set}/.claude}"
skill_names=(ask-codex ask-codex-with-context codex-implement list-codex-models set-codex-model)

for name in "${skill_names[@]}"; do
    [[ -d "$source_skills_root/$name" ]] || {
        printf 'Required skill source not found: %s\n' "$source_skills_root/$name" >&2
        exit 1
    }
    [[ -f "$source_skills_root/$name/SKILL.md" ]] || {
        printf 'Required SKILL.md not found: %s\n' "$source_skills_root/$name/SKILL.md" >&2
        exit 1
    }
done

mkdir -p -- "$destination_root/skills"
stage="$(mktemp -d "$destination_root/.add-codexcli-stage.XXXXXX")"
cleanup() { rm -rf -- "$stage"; }
trap cleanup EXIT
mkdir -p -- "$stage/skills"

for name in "${skill_names[@]}"; do
    cp -R -- "$source_skills_root/$name" "$stage/skills/$name"
done

for name in "${skill_names[@]}"; do
    final_dest="$destination_root/skills/$name"
    new_dest="$final_dest.new"
    old_dest="$final_dest.old"
    rm -rf -- "$new_dest"
    mv -- "$stage/skills/$name" "$new_dest"
    if [[ -e "$final_dest" ]]; then
        rm -rf -- "$old_dest"
        mv -- "$final_dest" "$old_dest"
    fi
    if ! mv -- "$new_dest" "$final_dest"; then
        if [[ -e "$old_dest" ]]; then
            if ! mv -- "$old_dest" "$final_dest" 2>/dev/null; then
                printf 'Rollback also failed for %s (leftover: %s)\n' "$name" "$old_dest" >&2
            fi
        fi
        printf 'Failed to promote new skill: %s\n' "$name" >&2
        exit 1
    fi
    rm -rf -- "$old_dest"
done

printf 'Claude Code用Skillをインストールしました。\n'
printf 'skills=%s\n' "$destination_root/skills"

#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd -- "$script_dir/.." && pwd)"
source_skills_root="$repository_root/.agents/skills"
destination_root="${1:-${HOME:?HOME is not set}/.gemini/antigravity-cli}"
scripts_root="${2:-${HOME:?HOME is not set}/.gemini/scripts}"
skill_names=(ask-codex ask-codex-with-context codex-implement list-codex-models set-codex-model)
script_names=(codex-wrapper.ps1 codex-wrapper.sh codex-verify.ps1 codex-verify.sh list-codex-models.ps1 list-codex-models.sh)

for name in "${skill_names[@]}"; do
    [[ -f "$source_skills_root/$name/SKILL.md" ]] || {
        printf 'Required skill source not found: %s\n' "$source_skills_root/$name/SKILL.md" >&2
        exit 1
    }
done
for name in "${script_names[@]}"; do
    [[ -f "$script_dir/$name" ]] || {
        printf 'Required script source not found: %s\n' "$script_dir/$name" >&2
        exit 1
    }
done

mkdir -p -- "$destination_root/skills" "$scripts_root"
stage="$(mktemp -d "$destination_root/.add-codexcli-stage.XXXXXX")"
cleanup() { rm -rf -- "$stage"; }
trap cleanup EXIT
mkdir -p -- "$stage/skills" "$stage/scripts"
escaped_scripts_root="${scripts_root//\\/\\\\}"
escaped_scripts_root="${escaped_scripts_root//&/\\&}"
escaped_scripts_root="${escaped_scripts_root//|/\\|}"

for name in "${skill_names[@]}"; do
    mkdir -p -- "$stage/skills/$name"
    sed \
        -e "s|{{SCRIPTS_ROOT}}|$escaped_scripts_root|g" \
        "$source_skills_root/$name/SKILL.md" > "$stage/skills/$name/SKILL.md"
done
for name in "${script_names[@]}"; do cp -- "$script_dir/$name" "$stage/scripts/$name"; done
for name in "${script_names[@]}"; do
    final_dest="$scripts_root/$name"
    new_dest="$final_dest.new"
    rm -f -- "$new_dest"
    cp -- "$stage/scripts/$name" "$new_dest"
    mv -f -- "$new_dest" "$final_dest"
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
        [[ ! -e "$old_dest" ]] || mv -- "$old_dest" "$final_dest"
        printf 'Failed to promote new skill: %s\n' "$name" >&2
        exit 1
    fi
    rm -rf -- "$old_dest"
done

printf 'Antigravity CLI用Skillをインストールしました。\n'
printf 'skills=%s\n' "$destination_root/skills"
printf 'scripts=%s\n' "$scripts_root"

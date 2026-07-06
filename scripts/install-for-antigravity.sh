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
for name in "${script_names[@]}"; do cp -- "$stage/scripts/$name" "$scripts_root/$name"; done
for name in "${skill_names[@]}"; do
    rm -rf -- "$destination_root/skills/$name"
    mv -- "$stage/skills/$name" "$destination_root/skills/$name"
done

printf 'Antigravity CLI用Skillをインストールしました。\n'
printf 'skills=%s\n' "$destination_root/skills"
printf 'scripts=%s\n' "$scripts_root"

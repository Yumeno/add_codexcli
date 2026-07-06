#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd -- "$script_dir/../.." && pwd)"
installer="$repository_root/scripts/install-for-antigravity.sh"
target="$(mktemp -d)"
trap 'rm -rf -- "$target"' EXIT
destination_root="$target/install root"
scripts_root="$target/shared scripts"
skill_names=(ask-codex ask-codex-with-context codex-implement list-codex-models set-codex-model)
script_names=(codex-wrapper.ps1 codex-wrapper.sh codex-verify.ps1 codex-verify.sh list-codex-models.ps1 list-codex-models.sh)

mkdir -p -- "$destination_root/skills/unrelated" "$destination_root/skills/ask-codex"
printf 'keep\n' > "$destination_root/skills/unrelated/keep.txt"
printf 'stale\n' > "$destination_root/skills/ask-codex/stale.txt"
bash "$installer" "$destination_root" "$scripts_root" >/dev/null

for name in "${skill_names[@]}"; do
    test -f "$destination_root/skills/$name/SKILL.md"
    ! grep -Fq '{{SCRIPTS_ROOT}}' "$destination_root/skills/$name/SKILL.md"
    grep -Fq "$scripts_root" "$destination_root/skills/$name/SKILL.md"
done
for name in "${script_names[@]}"; do test -f "$scripts_root/$name"; done
test "$(find "$scripts_root" -maxdepth 1 -type f | wc -l | tr -d ' ')" -eq "${#script_names[@]}"
test -f "$destination_root/skills/unrelated/keep.txt"
test ! -e "$destination_root/skills/ask-codex/stale.txt"
bash "$installer" "$destination_root" "$scripts_root" >/dev/null
test -z "$(find "$destination_root" -maxdepth 1 -type d -name '.add-codexcli-stage-*' -print -quit)"

printf 'PASS: Antigravity CLI installer\n'

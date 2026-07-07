#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd -- "$script_dir/../.." && pwd)"
installer="$repository_root/scripts/install-for-antigravity.sh"
target="$(mktemp -d)"
trap 'rm -rf -- "$target"' EXIT
destination_root="$target/install root"
skill_names=(ask-codex ask-codex-with-context codex-implement list-codex-models set-codex-model)

mkdir -p -- "$destination_root/skills/unrelated" "$destination_root/skills/ask-codex"
printf 'keep\n' > "$destination_root/skills/unrelated/keep.txt"
printf 'stale\n' > "$destination_root/skills/ask-codex/stale.txt"
bash "$installer" "$destination_root" >/dev/null

for name in "${skill_names[@]}"; do
    test -f "$destination_root/skills/$name/SKILL.md"
    test -d "$destination_root/skills/$name/scripts"
    ! grep -Fq '{{SCRIPTS_ROOT}}' "$destination_root/skills/$name/SKILL.md"
done
test -f "$destination_root/skills/ask-codex/scripts/codex-wrapper.sh"
test -f "$destination_root/skills/ask-codex/scripts/codex-wrapper.ps1"
test -f "$destination_root/skills/codex-implement/scripts/codex-verify.sh"
test -f "$destination_root/skills/codex-implement/scripts/codex-verify.ps1"
test -f "$destination_root/skills/list-codex-models/scripts/list-codex-models.sh"
test -f "$destination_root/skills/list-codex-models/scripts/list-codex-models.ps1"
test -f "$destination_root/skills/unrelated/keep.txt"
test ! -e "$destination_root/skills/ask-codex/stale.txt"

printf 'previous\n' > "$destination_root/skills/ask-codex/previous.txt"
chmod 555 "$destination_root/skills"
if mkdir "$destination_root/skills/.permission-probe" 2>/dev/null; then
    rmdir "$destination_root/skills/.permission-probe"
    printf 'SKIP: read-only destination enforcement is unavailable on this host\n'
else
    err_out="$(mktemp "${TMPDIR:-/tmp}/installer_err.XXXXXX")"
    if bash "$installer" "$destination_root" >/dev/null 2>"$err_out"; then
        printf 'Expected installer failure for read-only skills directory\n' >&2
        rm -f -- "$err_out"
        exit 1
    fi
    test -f "$destination_root/skills/ask-codex/previous.txt"
    grep -Fq 'Failed to promote new skill:' "$err_out" || {
        printf 'Expected "Failed to promote new skill:" diagnostic in stderr\n' >&2
        cat "$err_out" >&2
        rm -f -- "$err_out"
        exit 1
    }
    rm -f -- "$err_out"
fi
chmod 755 "$destination_root/skills"

mkdir -p -- "$destination_root/skills/ask-codex.new"
printf 'leftover\n' > "$destination_root/skills/ask-codex.new/leftover.txt"
bash "$installer" "$destination_root" >/dev/null
test -z "$(find "$destination_root" -maxdepth 1 -type d -name '.add-codexcli-stage-*' -print -quit)"
test -z "$(find "$destination_root/skills" -maxdepth 1 \( -name '*.new' -o -name '*.old' \) -print -quit)"

printf 'PASS: Antigravity CLI installer\n'
